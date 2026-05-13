-- =============================================================================
-- Nistula unified messaging — PostgreSQL schema (Part 2)
-- =============================================================================
-- Design goals:
--   • One canonical guest row; channel handles map to that guest.
--   • One messages table for the full timeline (inbound + outbound).
--   • Conversations tie a guest to a property and optionally a reservation.
--   • Inbound rows store classifier output (query_type + confidence).
--   • Outbound rows record how the reply left the system (AI vs agent path).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Enumerations (keeps invalid states out of the DB; easy to extend)
-- -----------------------------------------------------------------------------
CREATE TYPE channel_type AS ENUM (
    'whatsapp',
    'booking_com',
    'airbnb',
    'instagram',
    'direct'
);

CREATE TYPE message_direction AS ENUM ('inbound', 'outbound');

CREATE TYPE query_type AS ENUM (
    'pre_sales_availability',
    'pre_sales_pricing',
    'post_sales_checkin',
    'special_request',
    'complaint',
    'general_enquiry'
);

CREATE TYPE outbound_disposition AS ENUM (
    'auto_sent',                    -- AI draft sent without human edit
    'agent_edited_then_sent',       -- AI draft edited by staff, then sent
    'agent_composed'                -- Human wrote the outbound (no AI body)
);

CREATE TYPE conversation_status AS ENUM ('open', 'archived');

CREATE TYPE reservation_status AS ENUM (
    'inquiry',
    'confirmed',
    'checked_in',
    'checked_out',
    'cancelled'
);

-- -----------------------------------------------------------------------------
-- 1) Guest profiles — one row per real-world guest
-- -----------------------------------------------------------------------------
-- Why: business identity (name, contact) is separate from “how we reach them”
-- on WhatsApp vs Airbnb. Channel-specific IDs live in guest_channel_accounts.
-- -----------------------------------------------------------------------------
CREATE TABLE guests (
    guest_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    display_name      TEXT NOT NULL,
    primary_email     TEXT,
    primary_phone     TEXT,
    notes             TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE guests IS
    'Canonical guest. One human/booking party; many channel accounts can point here.';

COMMENT ON COLUMN guests.primary_email IS
    'Optional; used for dedupe, receipts, and CRM when available.';

-- -----------------------------------------------------------------------------
-- Channel identities → guest (unified inbox)
-- -----------------------------------------------------------------------------
-- Why: same person on WhatsApp and Airbnb has two external IDs; mapping both
-- to guest_id is what makes “unified” real.
-- -----------------------------------------------------------------------------
CREATE TABLE guest_channel_accounts (
    guest_channel_account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_id                 UUID NOT NULL REFERENCES guests (guest_id) ON DELETE CASCADE,
    channel                  channel_type NOT NULL,
    external_user_id         TEXT NOT NULL,
    display_name_on_channel  TEXT,
    is_verified              BOOLEAN NOT NULL DEFAULT false,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT guest_channel_accounts_unique_external UNIQUE (channel, external_user_id)
);

CREATE INDEX guest_channel_accounts_guest_idx ON guest_channel_accounts (guest_id);

COMMENT ON TABLE guest_channel_accounts IS
    'Maps a channel-specific handle (Airbnb thread user id, WhatsApp E.164, etc.) to guests.guest_id.';
COMMENT ON COLUMN guest_channel_accounts.external_user_id IS
    'Opaque id from the channel; format is channel-specific, stored as text.';

-- -----------------------------------------------------------------------------
-- Properties (minimal reference data)
-- -----------------------------------------------------------------------------
CREATE TABLE properties (
    property_id   TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE properties IS
    'Stable property catalog; property_id matches operational ids (e.g. villa-b1).';

-- -----------------------------------------------------------------------------
-- Reservations — link guest + property + booking reference
-- -----------------------------------------------------------------------------
CREATE TABLE reservations (
    reservation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_ref      TEXT NOT NULL UNIQUE,
    guest_id         UUID NOT NULL REFERENCES guests (guest_id) ON DELETE RESTRICT,
    property_id      TEXT NOT NULL REFERENCES properties (property_id) ON DELETE RESTRICT,
    check_in_date    DATE,
    check_out_date   DATE,
    status           reservation_status NOT NULL DEFAULT 'inquiry',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT reservations_dates_chk CHECK (
        check_in_date IS NULL
        OR check_out_date IS NULL
        OR check_out_date >= check_in_date
    )
);

CREATE INDEX reservations_guest_idx ON reservations (guest_id);
CREATE INDEX reservations_property_idx ON reservations (property_id);

COMMENT ON TABLE reservations IS
    'Stay record; conversations can point here once a booking exists (nullable for pure pre-sales).';

-- -----------------------------------------------------------------------------
-- Conversations — thread container: guest + property [+ optional reservation]
-- -----------------------------------------------------------------------------
CREATE TABLE conversations (
    conversation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_id        UUID NOT NULL REFERENCES guests (guest_id) ON DELETE RESTRICT,
    property_id     TEXT NOT NULL REFERENCES properties (property_id) ON DELETE RESTRICT,
    reservation_id  UUID REFERENCES reservations (reservation_id) ON DELETE SET NULL,
    status          conversation_status NOT NULL DEFAULT 'open',
    opened_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at       TIMESTAMPTZ,
    CONSTRAINT conversations_closed_chk CHECK (
        closed_at IS NULL OR closed_at >= opened_at
    )
);

CREATE INDEX conversations_guest_property_idx ON conversations (guest_id, property_id);
CREATE INDEX conversations_reservation_idx ON conversations (reservation_id);

COMMENT ON TABLE conversations IS
    'One timeline bucket: all messages for a guest around one property; reservation_id set when tied to a booking.';
COMMENT ON COLUMN conversations.reservation_id IS
    'NULL for pre-sales / general enquiries; set when the thread is (also) bound to a reservation.';

-- -----------------------------------------------------------------------------
-- 2–5) Unified messages — inbound + outbound in one table
-- -----------------------------------------------------------------------------
-- Why one table: single chronological feed per conversation; API and analytics
-- stay simple. Inbound-only and outbound-only columns are NULL where N/A,
-- enforced with CHECK so bad rows cannot be inserted.
-- -----------------------------------------------------------------------------
CREATE TABLE messages (
    message_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id         UUID NOT NULL REFERENCES conversations (conversation_id) ON DELETE CASCADE,
    direction               message_direction NOT NULL,
    channel                 channel_type NOT NULL,
    body_text               TEXT NOT NULL,
    occurred_at             TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Idempotency / sync with providers (webhook dedupe, backfill)
    external_message_id     TEXT,

    -- Inbound (classifier + confidence): required when direction = inbound
    query_type              query_type,
    confidence_score        NUMERIC(4, 3),

    -- Outbound: how the message left the building (requirement 4)
    outbound_disposition    outbound_disposition,

    -- Optional: outbound answers this specific inbound message
    in_reply_to_message_id  UUID REFERENCES messages (message_id) ON DELETE SET NULL,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT messages_inbound_payload_chk CHECK (
        direction <> 'inbound'
        OR (
            query_type IS NOT NULL
            AND confidence_score IS NOT NULL
            AND outbound_disposition IS NULL
            AND confidence_score >= 0
            AND confidence_score <= 1
        )
    ),
    CONSTRAINT messages_outbound_payload_chk CHECK (
        direction <> 'outbound'
        OR (
            outbound_disposition IS NOT NULL
            AND query_type IS NULL
            AND confidence_score IS NULL
        )
    )
);

CREATE UNIQUE INDEX messages_external_dedupe_idx
    ON messages (conversation_id, channel, external_message_id)
    WHERE external_message_id IS NOT NULL;

CREATE INDEX messages_conversation_timeline_idx ON messages (conversation_id, occurred_at);
CREATE INDEX messages_in_reply_to_idx ON messages (in_reply_to_message_id);

COMMENT ON TABLE messages IS
    'Unified message store: inbound rows carry query_type + confidence_score; outbound rows carry outbound_disposition.';
COMMENT ON COLUMN messages.query_type IS
    'Classifier output; stored only on inbound messages.';
COMMENT ON COLUMN messages.confidence_score IS
    'AI routing confidence for that inbound message; outbound does not repeat it (avoid duplication).';
COMMENT ON COLUMN messages.outbound_disposition IS
    'auto_sent vs agent-edited path vs fully agent-written; NULL on inbound.';
COMMENT ON COLUMN messages.in_reply_to_message_id IS
    'Links outbound reply to the inbound guest message it answers (optional but useful for threading).';

-- -----------------------------------------------------------------------------
-- Optional trigger: keep guests.updated_at fresh (lightweight polish)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER guests_set_updated_at
    BEFORE UPDATE ON guests
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER guest_channel_accounts_set_updated_at
    BEFORE UPDATE ON guest_channel_accounts
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER reservations_set_updated_at
    BEFORE UPDATE ON reservations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- HARDEST DESIGN DECISION (short answer for reviewers / interviews)
-- =============================================================================
-- The trickiest choice was modeling inbound vs outbound in ONE messages table
-- while still enforcing clean invariants: inbound rows must carry query_type +
-- confidence_score (per spec), outbound rows must record how the message was
-- sent (auto vs agent-edited vs human-only). Putting both shapes in one table
-- keeps a single timeline query simple, but it requires careful CHECK
-- constraints so we never store "inbound confidence" on an outbound row (which
-- would duplicate semantics and drift from truth). The alternative—splitting
-- inbound_messages and outbound_messages—makes timeline queries harder and
-- duplicates conversation_id/channel/time columns. We accepted nullable columns
-- plus CHECK constraints as the better tradeoff for a unified inbox product.
-- =============================================================================
