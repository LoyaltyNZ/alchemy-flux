# Change log

## v1.5.0

- Support Ruby >= 3; disallow Ruby version 2. [DS-4133](https://loyaltynz.atlassian.net/browse/DS-4133)

## v1.4.0

- Support Ruby 2.7

## v1.3.1

- Critical vulnerabilities update
  - Bump `rack` from `2.0.5` to `2.2.7`
  - Bump `rake` from `12.3.1` to `12.3.3`
  - Bump `yard` from `0.9.15` to `0.9.34`

## v1.3.0

- Routine maintenance pass, including general `bundle update` and minimum Ruby version bump from 2.4.2 to 2.4.4.
- Ruby 2.2 is no longer supported. Ruby 2.5 is now included in Travis test coverage.

## v1.2.1

- Allow unexpected service exceptions to be surfaced to force service exit, so an assumed-present orchestration layer can restart it; this attempts to alleviate issues with losses of connection to Rabbit that previously caused ignored exceptions leaving the connection permanently disabled.
- Maintenance `bundle update`.

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
