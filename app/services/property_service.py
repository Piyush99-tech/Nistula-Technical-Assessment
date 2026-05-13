PROPERTY_CONTEXTS = {
    "villa-b1": {
        "property": "Villa B1, Assagao, North Goa",
        "bedrooms": "3",
        "max_guests": "6",
        "private_pool": "Yes",
        "check_in": "2pm",
        "check_out": "11am",
        "base_rate": "INR 18,000 per night (up to 4 guests)",
        "extra_guest": "INR 2,000 per night per person",
        "wifi_password": "Nistula@2024",
        "caretaker": "Available 8am to 10pm",
        "chef_on_call": "Yes, pre-booking required",
        "availability_april_20_24": "Available",
        "cancellation": "Free up to 7 days before check-in",
    }
}


class PropertyContextNotFoundError(Exception):
    pass


def get_property_context(property_id: str) -> str:
    property_data = PROPERTY_CONTEXTS.get(property_id)

    if property_data is None:
        raise PropertyContextNotFoundError(
            f"No property context found for property_id '{property_id}'.",
        )

    return "\n".join(
        [
            f"Property: {property_data['property']}",
            f"Bedrooms: {property_data['bedrooms']}",
            f"Max guests: {property_data['max_guests']}",
            f"Private pool: {property_data['private_pool']}",
            f"Check-in: {property_data['check_in']}",
            f"Check-out: {property_data['check_out']}",
            f"Base rate: {property_data['base_rate']}",
            f"Extra guest: {property_data['extra_guest']}",
            f"WiFi password: {property_data['wifi_password']}",
            f"Caretaker: {property_data['caretaker']}",
            f"Chef on call: {property_data['chef_on_call']}",
            f"Availability April 20-24: {property_data['availability_april_20_24']}",
            f"Cancellation: {property_data['cancellation']}",
        ]
    )
