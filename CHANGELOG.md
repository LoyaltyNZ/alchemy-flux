version 1.0
- removed MessagePack
- `send_message_to_service` now `send_request_to_service`
- `send_message_to_resource` now `send_request_to_resource`
- `send_message_to_queue` refactored to force HTTP packet format and is now `send_message_to_service`
- `send_message_to_resource` added to allow non-response messages sent to resources
- All message are now HTTP packet format, so logging must be updated.
