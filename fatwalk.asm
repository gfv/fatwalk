format PE console
entry start
; ������ �����������
include 'win32a.inc'
include 'fat_structs.inc'

include 'smartmacro.inc'


section '.text' code executable
start:
	; ���� ����� ��������� linux, �� ��� ����� ���������� - ����� libc
	cinvoke __getmainargs, argc, argv, penvdata, pwildcard, pstartinfo
	cmp [argc], 2
	jl print_usage
	cmp [argc], 3
	je print_usage
	cmp [argc], 4
	jg print_usage

	mov esi, [argv]
	add esi, 4

	; �������� ������� ����
	cinvoke fopen, [esi], file_mode
	test eax, eax
	jz print_usage
	mov [fhandle], eax

	; ��������� ��������� FAT32
	cinvoke fread, bpb_head, bpb_head_size, 1, eax
	cinvoke fread, bpb32, bpb32_size, 1, [fhandle]

precalculations:
	; ����� ������� ����� ��������, ����� ����� ���� ������ fseek'���
	xor eax, eax
	xor edx, edx
	mov ax, [bpb_head.BytesPerSec]
	mov dl, [bpb_head.SecPerClus]
	mul dx
	mov [bytes_per_cluster], eax

	; �������� FAT ������������ ������ �����
	xor eax, eax
	mov ax, [bpb_head.RsvdSecCnt]
	sector_to_offset eax
	storeq fat_offset

	; �������� ��������� ������������ ������ �����
	xor edx, edx
	mov dl, [bpb_head.NumFATs]
	mov eax, [bpb32.FATSz32]
	mul edx
	xor ebx, ebx
	mov bx, [bpb_head.RsvdSecCnt]
	add eax, ebx
	sector_to_offset eax
	storeq clusters_offset

	; ����� ���������� ��������, � ��� ���������� ��������� ������
	;  bytes_per_cluster - ���� � ��������
	;  fat_offset - ������ ������ FAT �� ������ �����
	;  clusters_offset - ������ ������� (#2) ��������

payload:
	cmp [argc], 4
	je parse_operation
	;mov eax, [bpb32.RootClus]
	;stdcall follow_dir, eax, zero_callback, compare_lfn
	jmp closef

parse_operation:
	mov esi, [argv]
	add esi, 8 ; ������ ��������!
	mov esi, [esi] ; fuck logic
	cmp word [esi], "ls"
	je ls
	cmp word [esi], "ex"
	je extract
	jmp print_usage
	
ls:
	mov eax, [bpb32.RootClus]
	mov [next_dir], eax
	mov esi, [argv]
	add esi, 12 ; ������ ��������!
	mov esi, [esi] ; argv - ��� ��������� �� ������ ���������� �� ������� [��������]. yo dawg

.cd_inside:
	cinvoke strtok, esi, tok_sep
	test eax, eax
	jz .no_more_tokens
	mov ebx, eax
	push ebx
	invoke strlen, eax
	invoke MultiByteToWideChar,CP_ACP,0,ebx,eax,lookup_mb_buffer, 512
	mov eax, [next_dir] 
	mov [next_dir], -1
	stdcall follow_dir, eax, ls_short_callback, ls_long_callback
	pop ebx
	cmp [next_dir], -1
	je .not_found
	xor esi, esi
	jmp .cd_inside

.no_more_tokens: ; � ��� �� �������� ������ �������, ���� ����� ���������� -> �� �� �����
	stdcall follow_dir, [next_dir], print_sname, print_lfn
	jmp closef

.not_found:
	cinvoke printf, file_not_found, ebx
	jmp closef
	
extract:
	mov eax, [bpb32.RootClus]
	mov [next_dir], eax
	mov [file_cluster], 0
	mov esi, [argv]
	add esi, 12
	mov esi, [esi]
	
.cd_inside:
	cinvoke strtok, esi, tok_sep
	test eax, eax
	jz .no_more_tokens ; ���� ������ �� �������� �������, �� ������ �����, � file_cluster - ������� �����
	
	test [next_dir], -1 ; ���� ��� ��� �������� ������, � ���������� ���������, �� �� ���� ��� � �� �����
	jz .not_found
	
	mov ebx, eax
	push ebx
	invoke strlen, eax
	invoke MultiByteToWideChar,CP_ACP,0,ebx,eax,lookup_mb_buffer, 512
	mov eax, [next_dir] 
	mov [next_dir], -1
	
	stdcall follow_dir, eax, ex_short_callback, ex_long_callback
	pop ebx
	cmp [next_dir], -1 ; ���� next_dir �� ����������, �� �� ������ �� ����� ����� � ����� ������
	je .not_found ; ���� �� ����� ���������� - ��� ��� �� �� �������, ���� �� ���� - 0
	
	xor esi, esi
	jmp .cd_inside

.no_more_tokens: ; � ��� �� �������� ������ �������, ���� ����� ���������� -> �� �� �����
	test [file_cluster], -1
	jz .not_found
	; ���! �� ����� ���� ��������.
	cinvoke _wfopen, lookup_mb_buffer, w_file_write_mode
	test eax, eax
	push eax
	jz .fopen_fail
	stdcall dump_cluster_chain, [file_cluster], [file_length], eax
	pop eax
	cinvoke fclose, eax
	jmp closef
	

.not_found:
	cinvoke printf, file_not_found, ebx
	jmp closef

.fopen_fail:
	cinvoke printf, fmt_fopen_fail
	jmp closef

; ��� ����������� �������
print_usage:
	cinvoke printf, usage
	jmp halt

; ��������� ������: ��� ������ �� ��������� �� ������, ��� ������ �������� ���� ���������
closef: cinvoke fclose, [fhandle]
halt:	invoke ExitProcess, 0

proc zero_callback, rec:DWORD
	mov eax, 1
	ret
	endp

proc ls_short_callback, rec:DWORD
	push esi
	mov esi, [rec]
	
	virtual at esi
		.dirent FAT32_dirent
	end virtual
	test [.dirent.Attribute], ATTR_DIR
	jz .not_found
	
	stdcall convert_short_directory_name, esi
	cinvoke _mbsicmp, multibyte_buffer, lookup_mb_buffer
	test eax, eax
	jnz .not_found
;	jmp .found
	
;.check_filename:
;	stdcall convert_short_filename, esi
;	cinvoke _mbsicmp, multibyte_buffer, lookup_mb_buffer
;	test eax, eax
;	jnz .not_found

.found:
	mov ax, word [.dirent.StartClusterHigh]
	shl eax, 16
	mov ax, word [.dirent.StartCluster]
	mov [next_dir], eax
	xor eax, eax
	jmp .final

.not_found:
	mov eax, 1
.final:
	pop esi
	ret
	endp

proc ls_long_callback, rec:DWORD, lfn:DWORD
	push esi
	mov esi, [rec]
	virtual at esi
		.dirent FAT32_dirent
	end virtual
	test [.dirent.Attribute], ATTR_DIR
	jz .not_found
	
	cinvoke _mbsicmp, [lfn], lookup_mb_buffer
	test eax, eax
	jnz .not_found
	
	mov ax, word [.dirent.StartClusterHigh]
	shl eax, 16
	mov ax, word [.dirent.StartCluster]
	mov [next_dir], eax
	xor eax, eax 
	jmp .final

.not_found:
	mov eax, 1

.final:
	pop esi
	ret
	endp


proc ex_short_callback, rec:DWORD
	push esi
	mov esi, [rec]
	
	virtual at esi
		.dirent FAT32_dirent
	end virtual
	
	test [.dirent.Attribute], ATTR_DIR
	jz .file
	
.directory:
	stdcall convert_short_directory_name, esi
	cinvoke _mbsicmp, multibyte_buffer, lookup_mb_buffer
	test eax, eax
	jnz .not_found
	
	mov ax, word [.dirent.StartClusterHigh]
	shl eax, 16
	mov ax, word [.dirent.StartCluster]
	mov [next_dir], eax
	xor eax, eax
	jmp .final
	
.file:
	stdcall convert_short_filename, esi
	cinvoke _mbsicmp, multibyte_buffer, lookup_mb_buffer
	test eax, eax
	jnz .not_found
	
	mov ax, word [.dirent.StartClusterHigh]
	shl eax, 16
	mov ax, word [.dirent.StartCluster]
	mov ecx, [.dirent.Size]
	mov [file_cluster], eax
	mov [file_length], ecx
	xor eax, eax
	mov [next_dir], 0
	jmp .final

.not_found:
	mov eax, 1
.final:
	pop esi
	ret
	endp

proc ex_long_callback, rec:DWORD, lfn:DWORD
	cinvoke _mbsicmp, [lfn], lookup_mb_buffer
	test eax, eax
	jnz .not_found

	mov edx, [rec]
	virtual at edx
		.dirent FAT32_dirent
	end virtual
	mov ax, word [.dirent.StartClusterHigh]
	shl eax, 16
	mov ax, word [.dirent.StartCluster]
	test [.dirent.Attribute], ATTR_DIR
	pop esi
	jz .file

.directory:
	mov [next_dir], eax
	xor eax, eax
	ret
	
.file:
	mov [file_cluster], eax
	mov ecx, [.dirent.Size]
	mov [file_length], ecx
	xor eax, eax
	mov [next_dir], 0
	ret

.not_found:
	mov eax, 1
	ret
	endp



proc print_sname, rec:DWORD
	mov eax, [rec]
	cinvoke printf, fmt_83, eax
	mov eax, 1
	ret
	endp

proc print_lfn, rec:DWORD, lfn:DWORD
	mov eax, [lfn]
	cinvoke wprintf, w_fmt_s, eax
	mov eax, 1
	ret
	endp

;
; � ������ ����� ���������
;

; ������������� �� ����������.
; cluster - ������ ������� ����������
; short_callback - ������� ��� ���������� ����� � �������� ������. ������ ���� stdcall �
;                  ��������� ����� ���� dword - ��������� �� ������ ���������� � �����.
; lfn_callback - ������� ��� ���������� ����� � ������� ������. ������ ���� stdcall � ���������
;                ��� ���������: ��������� �� ������ ���������� � ��������� �� ������ ��������.
; �������� �������: ���, ��� ������
proc follow_dir, cluster:DWORD, short_callback:DWORD, lfn_callback:DWORD
	mov eax, [cluster]
	push eax
	call read_cluster
.init_counters:
	; esi - ��������� �� ������� ������
	; ebx - ������� ����������� �������� ������� � ��������
	mov esi, cluster_buffer
	mov edi, lfn_buffer_end
	mov byte [edi], 0
	mov ebx, [bytes_per_cluster]
	shr ebx, 5 ; ������ ������ �� 32 �����
.parse_entry:
	virtual at esi
	  .dirent FAT32_dirent
	end virtual
	; ���� ������ ���� �������� = 0x00 -> ��� ���������
	test [.dirent.Name], 0xff
	jz .no_more_records
	; ���� � �������� ����� RO|HID|SYS|VL - ��� LFN
	cmp [.dirent.Attribute], 0x0f
	jne .process_alias
	call lfn_record
	jmp .next_entry

; ���� �� ����� ����, �� ����� ���� alias, � ��� ����� ����������
; ��� �� �����: edi � ������� ������� ����� � LFN, lfn_buffer � ���������� ������� 
; �������� �������: eax, ecx, edx, edi
.process_alias:
	cmp edi, lfn_buffer_end 
	jz .process_83
.process_lfn:
	mov eax, [lfn_callback]
	stdcall eax, esi, edi
	test eax, eax
	jz .no_more_records
	mov edi, lfn_buffer_end
	jmp .next_entry

; ��� �� LFN, � ������ ���� �������� ���. �������� ���, �������� ���, ��� ��� ��������
; � ������ 11 ������ ������.
; ��� �� �����: esi � ������� ������ ������ ����������
; �������� �������: eax, ecx, edx
.process_83:
	mov eax, [short_callback]
	stdcall eax, esi
	test eax, eax
	jz .no_more_records
   ;jmp .next_entry

; � ���� ������� ���, ����� ������� ������ � ���������
; �� �����: esi � ������� ������, ebx � ����������� ���������� 
; �� ������: esi � ������� ���������, ebx � ����������� ����������
.next_entry:
	; ��������� �� ����� ������
	add esi, 32
	dec ebx
	jnz .parse_entry

; � ���� �������� ������ ���������, ����� ��������� ��������� �������
; �� ������� ����� ����� ����� ��������, ������� �� ������ ��� ������.
; ������� ���, ������ ��������� �� ��� � ������ ��� ����� � ����
; �������� �������: eax, ecx, edx, ������� �����
.next_cluster:
	pop eax
	call read_next_cluster
	push eax
	jnc .init_counters

.no_more_records:
	pop eax
	ret
	endp

proc dump_cluster_chain, zero_cluster:DWORD, len:DWORD, fouthandle:DWORD
	mov ebx, [len]
	mov eax, [zero_cluster]
	push eax
	call read_cluster
.rd_cluster:
	cmp ebx, [bytes_per_cluster]
	jle .partial_cluster
	cinvoke fwrite, cluster_buffer, [bytes_per_cluster], 1, [fouthandle]
	sub ebx, [bytes_per_cluster]
	pop eax
	call read_next_cluster
	push eax
	jmp .rd_cluster

.partial_cluster:
	cinvoke fwrite, cluster_buffer, ebx, 1, [fouthandle]
	pop eax
	ret
	endp

;
; here be dragons
;

; �������, ������� ��������� ��������� �� ������ ������ cluster_buffer � esi
; � ���������� �������� LFN �� ���� � ������ lfn_buffer. ����� ����� ��� ����������
; edi � ������ ���������� ������ � ������������.
; ���������: edi, ����������� �� ������ ���������� ������ � ������ LFN
; �������� �������: ecx, edi, [lfn_buffer]
proc lfn_record
	virtual at ebx
	  .lfnent LFN_dirent
	end virtual
	push ebx
	mov ebx, esi
	test [.lfnent.Sequence], 0x40
	jnz .reset_lfn_pointer
.copy_lfn_part:
	sub edi, 26
	push esi

; fasm'� ���-�� �� �������� � ������� LFN, ��� ��� ������ �� lea � ��������
macro esi_load_with_ebx_offset off, len
{
	lea esi, [ebx+off]
	mov ecx, len
	rep movsb
}
	
	esi_load_with_ebx_offset 0x01, 10
	esi_load_with_ebx_offset 0x0e, 12
	esi_load_with_ebx_offset 0x1c, 4

	pop esi
	pop ebx
	sub edi, 26
	jmp .reloaded
	
.reset_lfn_pointer:
	mov edi, lfn_buffer_end
	jmp .copy_lfn_part

.reloaded:
	ret
	endp

; ����������� ��������� �������, ��������� �� #eax
; CF=0 -> ���������, � ������
; CF=1 -> ��� ��� ��������� ������� � �������
; �������� �������: eax, ecx, edx, dword_buffer, cluster_buffer 
proc read_next_cluster
	xor edx, edx
	shl eax, 2
	add eax, dword [fat_offset]
	adc edx, dword [fat_offset+4]
	call read_dword
	and eax, 0x0fffffff
	cmp eax, 0x0fffffff
	je .no_more_clusters
	push eax
	call read_cluster
	clc
	pop eax
	ret
.no_more_clusters:
	stc
	ret
	endp

; hexdump len ���� �� ������ ad
proc hexdump, ad:DWORD, len:DWORD
	push esi
	push ebx
	mov esi, [ad]
	mov ebx, [len]
.dump:
	test ebx, ebx
	jz .no_data_left
	xor eax, eax
	mov al, byte [esi]
	cinvoke printf, fmt_hexbyte, eax
	dec ebx
	inc esi
	test esi, 0xf
	jnz .dump
	cinvoke printf, fmt_newline
	jmp .dump
.no_data_left:
	cinvoke printf, fmt_newline
	pop ebx
	pop esi
	ret
	endp

; ������� � ����� �� ������ edx:eax.
; libc-dependent: ��� ������� ������ ����� ����� ��������������� 64-������ fseek
; �������� �������: eax, ecx, edx
proc long_fseek
	push 0
	push edx ; ��� ������ ������� � ���������� � __int64 ������� push ������� dword
	push eax ; ����� �������
	push [fhandle]
	call [fseeki64]
	add esp, 16
	ret
	endp

; ��������� dword �� ������� �� edx:eax
; �������� �������: eax, ecx, edx, �������� dword_buffer
proc read_dword
	call long_fseek
	cinvoke fread, dword_buffer, 4, 1, [fhandle]
	mov eax, [dword_buffer]
	ret
	endp

; ��������� ������� � ������� eax
; �������� �������: eax, ecx, edx, dword_buffer, cluster_buffer
proc read_cluster
	sub eax, 2
	xor edx, edx
	mov edx, [bytes_per_cluster]
	mul edx
	add eax, dword [clusters_offset]
	adc edx, dword [clusters_offset+4]
	call long_fseek
	cinvoke fread, cluster_buffer, [bytes_per_cluster], 1, [fhandle]
	test eax, eax
	jz closef
	ret
	endp


proc flush_multibyte_buffer
	int 3 ; ����
	push ecx
	push edi
	xor eax, eax
	mov ecx, (512/4)
	mov edi, multibyte_buffer
	rep stosd
	pop edi
	pop ecx
	ret
	endp


; ���������� ��� ����� 8.3 � LFN-�������� ������.
proc convert_short_filename, short_name:DWORD
	push esi
	push edi
	mov esi, [short_name]
	add esi, 7
	mov ecx, 8
	std
.find_last_letter:
	dec ecx
	jz .empty
	lodsb
	cmp al, ' '
	je .find_last_letter

	inc ecx ; ����� �������� �����
	mov esi, [short_name]
	cld
	mov edi, short_name_buffer
	rep movsb
	mov byte [edi], '.'
	inc edi ; ��������� �� ������ �� ������
	
	mov ecx, 3
	mov esi, [short_name]
	add esi, 8 ; ��������� �� ����������

.store_extension:
	lodsb
	cmp al, 0x20
	je .empty
	stosb
	loop .store_extension

.expand_name:
	sub edi, short_name_buffer
	invoke MultiByteToWideChar, CP_ACP, 0, short_name_buffer, edi, multibyte_buffer, 512
	mov eax, edi
.empty:
	pop edi
	pop esi
	ret
	endp

; ���������� ��� ���������� � LFN. �� ����������� �����, � ������� �� convert_short_filename
proc convert_short_directory_name, short_name:DWORD
	push esi ; it's a freakin' local variable, mate
	mov esi, [short_name]
	add esi, 10
	mov ecx, 11
	std
.find_last_letter:
	dec ecx
	jz .empty ; �� �������� �� ������ ���������
	lodsb
	cmp al, ' '
	je .find_last_letter
	
	inc ecx
	cld
	mov esi, [short_name]
	mov edi, short_name_buffer
	rep movsb
	sub edi, short_name_buffer
	invoke MultiByteToWideChar, CP_ACP, 0, short_name_buffer, edi, multibyte_buffer, 512
	mov eax, edi ; ������ ����� �������� ����������

.empty:
	pop esi
	ret
	endp

section '.bss' data readable writeable
include 'vars.inc'

section '.rdata' data readable
include 'strings.inc'
tst db 'NTOSKRNLEXE', 0

section '.idata' data readable import
include 'imports.inc'