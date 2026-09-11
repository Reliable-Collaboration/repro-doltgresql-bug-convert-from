-- convert_to: text to bytes in the UTF8 encoding.
SELECT convert_to('hello', 'UTF8');

-- convert_from: the same bytes back to text.
SELECT convert_from('\x68656c6c6f'::bytea, 'UTF8');
