-- =============================================================================
-- Nistula unified messaging — PostgreSQL schema (Part 2)
-- =============================================================================
-- One guest across channels, one messages table, conversations tied to guest
-- and optional reservation. Inbound: query + confidence. Outbound: how sent.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Types (allowed values in the database)
-- -----------------------------------------------------------------------------
CREATE TYPE channel AS ENUM (
    'whatsapp',
    'booking_com',
    'airbnb',
    'instagram',
    'direct'
);

CREATE TYPE msg_direction AS ENUM ('inbound', 'outbound');

CREATE TYPE query_kind AS ENUM (
    'pre_sales_availability',
    'pre_sales_pricing',
    'post_sales_checkin',
    'special_request',
    'complaint',
    'general_enquiry'
);

-- How an outbound message actually left (AI vs human path)
CREATE TYPE send_kind AS ENUM (
    'auto_sent',
    'agent_edited_then_sent',
    'agent_composed'
);

CREATE TYPE thread_status AS ENUM ('open', 'archived');

CREATE TYPE booking_status AS ENUM (
    'inquiry',
    'confirmed',
    'checked_in',
    'checked_out',
    'cancelled'
);

-- -----------------------------------------------------------------------------
-- Guests — one row per person / party
-- -----------------------------------------------------------------------------
CREATE TABLE guests (
    guest_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    display_name  TEXT NOT NULL,
    email         TEXT,
    phone         TEXT,
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE guests IS 'The real guest; one row per person or booking party.';
COMMENT ON COLUMN guests.email IS 'Optional; helps match the same person later.';
COMMENT ON COLUMN guests.phone IS 'Optional; helps match the same person later.';

-- -----------------------------------------------------------------------------
-- Guest channels — “this WhatsApp / Airbnb login is that guest”
-- -----------------------------------------------------------------------------
CREATE TABLE guest_channels (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_id        UUID NOT NULL REFERENCES guests (guest_id) ON DELETE CASCADE,
    channel         channel NOT NULL,
    channel_user_id TEXT NOT NULL,
    name_on_channel TEXT,
    verified        BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_one_guest_per_channel_login UNIQUE (channel, channel_user_id)
);

CREATE INDEX ix_guest_channels_guest ON guest_channels (guest_id);

COMMENT ON TABLE guest_channels IS
    'Links a channel login (phone, Airbnb user id, etc.) to guests.guest_id so all channels show one inbox.';
COMMENT ON COLUMN guest_channels.channel_user_id IS
    'Opaque id from the channel (format depends on WhatsApp, Airbnb, etc.).';

-- -----------------------------------------------------------------------------
-- Properties
-- -----------------------------------------------------------------------------
CREATE TABLE properties (
    property_id TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE properties IS 'Villas / rooms; property_id matches your app (e.g. villa-b1).';

-- -----------------------------------------------------------------------------
-- Reservations — guest + property + booking ref
-- -----------------------------------------------------------------------------
CREATE TABLE reservations (
    reservation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_ref    TEXT NOT NULL UNIQUE,
    guest_id       UUID NOT NULL REFERENCES guests (guest_id) ON DELETE RESTRICT,
    property_id    TEXT NOT NULL REFERENCES properties (property_id) ON DELETE RESTRICT,
    check_in       DATE,
    check_out      DATE,
    status         booking_status NOT NULL DEFAULT 'inquiry',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_booking_dates CHECK (
        check_in IS NULL OR check_out IS NULL OR check_out >= check_in
    )
);

CREATE INDEX ix_reservations_guest ON reservations (guest_id);
CREATE INDEX ix_reservations_property ON reservations (property_id);

COMMENT ON TABLE reservations IS 'A stay; threads can point here once there is a booking.';

-- -----------------------------------------------------------------------------
-- Conversations — one message thread (guest + property, optional booking)
-- -----------------------------------------------------------------------------
CREATE TABLE conversations (
    conversation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_id        UUID NOT NULL REFERENCES guests (guest_id) ON DELETE RESTRICT,
    property_id     TEXT NOT NULL REFERENCES properties (property_id) ON DELETE RESTRICT,
    reservation_id  UUID REFERENCES reservations (reservation_id) ON DELETE SET NULL,
    status          thread_status NOT NULL DEFAULT 'open',
    opened_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at       TIMESTAMPTZ,
    CONSTRAINT chk_thread_closed_after_open CHECK (
        closed_at IS NULL OR closed_at >= opened_at
    )
);

CREATE INDEX ix_conversations_guest ON conversations (guest_id, property_id);
CREATE INDEX ix_conversations_booking ON conversations (reservation_id);

COMMENT ON TABLE conversations IS
    'All messages for one guest about one property; reservation_id empty before a booking exists.';
COMMENT ON COLUMN conversations.reservation_id IS 'Set when the chat is tied to a reservation.';

-- -----------------------------------------------------------------------------
-- Messages — inbound and outbound in one timeline
-- -----------------------------------------------------------------------------
CREATE TABLE messages (
    message_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations (conversation_id) ON DELETE CASCADE,
    direction        msg_direction NOT NULL,
    channel          channel NOT NULL,
    body_text        TEXT NOT NULL,
    msg_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Same webhook twice? Same id from WhatsApp? Skip dupes using this.
    channel_msg_id   TEXT,

    -- Inbound only: classifier output
    query_type       query_kind,
    confidence       NUMERIC(4, 3),

    -- Outbound only: auto vs agent-edited vs human-only
    how_sent         send_kind,

    -- Outbound reply can point at the guest message it answers (optional)
    reply_to_id      UUID REFERENCES messages (message_id) ON DELETE SET NULL,

    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_inbound_shape CHECK (
        direction <> 'inbound'
        OR (
            query_type IS NOT NULL
            AND confidence IS NOT NULL
            AND how_sent IS NULL
            AND confidence >= 0
            AND confidence <= 1
        )
    ),
    CONSTRAINT chk_outbound_shape CHECK (
        direction <> 'outbound'
        OR (
            how_sent IS NOT NULL
            AND query_type IS NULL
            AND confidence IS NULL
        )
    )
);

-- One row per (conversation, channel, id-from-channel): stops duplicate webhooks
CREATE UNIQUE INDEX uq_messages_same_channel_msg
    ON messages (conversation_id, channel, channel_msg_id)
    WHERE channel_msg_id IS NOT NULL;

CREATE INDEX ix_messages_newest_first ON messages (conversation_id, msg_at DESC);
CREATE INDEX ix_messages_reply ON messages (reply_to_id);

COMMENT ON TABLE messages IS
    'All messages in one place: inbound has query_type + confidence; outbound has how_sent.';
COMMENT ON COLUMN messages.channel_msg_id IS
    'Id from the channel so we do not store the same inbound message twice.';
COMMENT ON COLUMN messages.confidence IS 'Routing confidence for this inbound message only.';
COMMENT ON COLUMN messages.how_sent IS 'auto_sent, agent edited then sent, or agent wrote it.';
COMMENT ON COLUMN messages.reply_to_id IS 'If outbound, which inbound (or other) message this replies to.';
COMMENT ON COLUMN messages.msg_at IS 'When this message happened; use for timeline ordering.';


