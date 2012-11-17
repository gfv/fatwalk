fmt_s db '%s', 10, 0
w_fmt_s db '%', 0, 's', 0, 10, 0, 0, 0
fmt_eight_byte_str db '%.8s', 10, 0
fmt_83 db '%.11s', 10, 0
fmt_slash db '/', 0
fmt_ubyte db '%hhu', 10, 0
fmt_uword db '%hu', 10, 0
fmt_udword db '%u', 10, 0
fmt_hexbyte db '%02hhx ', 0
fmt_newline db 10, 0
fmt_dir db '[directory] { ', 10, 0
fmt_dir_end db '}', 10, 0
file_not_found db 'File not found: %s', 10, 0
fmt_fopen_fail db 'fopen() failed :<', 10, 0
tok_sep db '/', 0

soskok db 'soskok', 10, 0

file_mode db 'rb', 0
file_write_mode db 'wb', 0
w_file_write_mode db 'w', 0, 'b', 0, 0, 0

usage db 'use: fatwalk.exe <image file> [ls <dir> | ex <path>]', 10, \
		 '       ls <dir> - ls files in a directory', 10, \
		 '       ex <path> - extract a file from the image', 10, 0