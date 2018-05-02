# Change log

## v1.2.1

- Handle unexpected service exceptions better
- Maintenance `bundle update yard`

## v1.2.0

- Added `AlchemyFlux::VERSION` and `AlchemyFlux::DATE`.
- Requires Ruby v2.2.7 or later, defaults to Ruby 2.4.1.
- Maintenance `bundle update`.

## v1.1.0

- Rack v2.x, requiring Ruby v2.2.5 or later, default to Ruby 2.3.1.

## v1.0.0

- Removed MessagePack
- `send_message_to_service` now `send_request_to_service`
- `send_message_to_resource` now `send_request_to_resource`
- `send_message_to_queue` refactored to force HTTP packet format and is now `send_message_to_service` pass logging packet inside of `body` to `send_message_to_service`
- `send_message_to_resource` added to allow non-response messages sent to resources
- All message are now HTTP packet format, so logging must be updated.
