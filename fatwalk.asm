format PE console
entry start
; обожаю комментарии
include 'win32a.inc'
include 'fat_structs.inc'

include 'smartmacro.inc'


section '.text' code executable
start:
	; если очень захочется linux, то это можно переписать - слава libc
	cinvoke __getmainargs, argc, argv, penvdata, pwildcard, pstartinfo
	cmp [argc], 2
	jl print_usage
	cmp [argc], 3
	je print_usage
	cmp [argc], 4
	jg print_usage

	mov esi, [argv]
	add esi, 4

	; пытаемся открыть файл
	cinvoke fopen, [esi], file_mode
	test eax, eax
	jz print_usage
	mov [fhandle], eax

	; считываем заголовки FAT32
	cinvoke fread, bpb_head, bpb_head_size, 1, eax
	cinvoke fread, bpb32, bpb32_size, 1, [fhandle]

precalculations:
	; сразу считаем длину кластера, чтобы можно было удобно fseek'ать
	xor eax, eax
	xor edx, edx
	mov ax, [bpb_head.BytesPerSec]
	mov dl, [bpb_head.SecPerClus]
	mul dx
	mov [bytes_per_cluster], eax

	; смещение FAT относительно начала файла
	xor eax, eax
	mov ax, [bpb_head.RsvdSecCnt]
	sector_to_offset eax
	storeq fat_offset

	; смещение кластеров относительно начала файла
	xor edx, edx
	mov dl, [bpb_head.NumFATs]
	mov eax, [bpb32.FATSz32]
	mul edx
	xor ebx, ebx
	mov bx, [bpb_head.RsvdSecCnt]
	add eax, ebx
	sector_to_offset eax
	storeq clusters_offset

	; после предыдущих операций, у нас появляются следующие знания
	;  bytes_per_cluster - байт в кластере
	;  fat_offset - оффсет начала FAT от начала файла
	;  clusters_offset - оффсет первого (#2) кластера

payload:
	cmp [argc], 4
	je parse_operation
	;mov eax, [bpb32.RootClus]
	;stdcall follow_dir, eax, zero_callback, compare_lfn
	jmp closef

parse_operation:
	mov esi, [argv]
	add esi, 8 ; второй аргумент!
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
	add esi, 12 ; третий аргумент!
	mov esi, [esi] ; argv - это указатель на массив указателей на массивы [символов]. yo dawg

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

.no_more_tokens: ; у нас не осталось больше токенов, куда нужно переходить -> мы на месте
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
	jz .no_more_tokens ; если больше не осталось токенов, то скорее всего, в file_cluster - кластер файла
	
	test [next_dir], -1 ; если все еще остались токены, а директории кончились, то мы файл так и не нашли
	jz .not_found
	
	mov ebx, eax
	push ebx
	invoke strlen, eax
	invoke MultiByteToWideChar,CP_ACP,0,ebx,eax,lookup_mb_buffer, 512
	mov eax, [next_dir] 
	mov [next_dir], -1
	
	stdcall follow_dir, eax, ex_short_callback, ex_long_callback
	pop ebx
	cmp [next_dir], -1 ; если next_dir не изменилось, то мы просто не нашли файла с таким именем
	je .not_found ; если бы нашли директорию - там был бы ее кластер, если бы файл - 0
	
	xor esi, esi
	jmp .cd_inside

.no_more_tokens: ; у нас не осталось больше токенов, куда нужно переходить -> мы на месте
	test [file_cluster], -1
	jz .not_found
	; ага! мы нашли файл кластера.
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

; нас неправильно вызвали
print_usage:
	cinvoke printf, usage
	jmp halt

; обработка ошибок: чем раньше мы наткнемся на ошибку, тем меньше действий надо совершить
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
; а теперь пошли процедуры
;

; Итерироваться по директории.
; cluster - первый кластер директории
; short_callback - коллбэк при нахождении файла с коротким именем. должен быть stdcall и
;                  принимать ровно один dword - указатель на запись директории и файле.
; lfn_callback - коллбэк при нахождении файла с длинным именем. должен быть stdcall и принимать
;                два параметра: указатель на запись директории и указатель на начало названия.
; побочные эффекты: все, что попало
proc follow_dir, cluster:DWORD, short_callback:DWORD, lfn_callback:DWORD
	mov eax, [cluster]
	push eax
	call read_cluster
.init_counters:
	; esi - указатель на текущую запись
	; ebx - сколько максимально осталось записей в кластере
	mov esi, cluster_buffer
	mov edi, lfn_buffer_end
	mov byte [edi], 0
	mov ebx, [bytes_per_cluster]
	shr ebx, 5 ; каждая запись по 32 байта
.parse_entry:
	virtual at esi
	  .dirent FAT32_dirent
	end virtual
	; если первый байт названия = 0x00 -> все кончилось
	test [.dirent.Name], 0xff
	jz .no_more_records
	; если в атрибуте файла RO|HID|SYS|VL - это LFN
	cmp [.dirent.Attribute], 0x0f
	jne .process_alias
	call lfn_record
	jmp .next_entry

; если мы дошли сюда, то перед нами alias, и его можно обработать
; что на входе: edi с адресом первого байта в LFN, lfn_buffer с корректной строкой 
; побочные эффекты: eax, ecx, edx, edi
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

; это не LFN, а вполне себе короткое имя. печатаем его, польуясь тем, что оно хранится
; в первых 11 байтах записи.
; что на входе: esi с адресом начала записи директории
; побочные эффекты: eax, ecx, edx
.process_83:
	mov eax, [short_callback]
	stdcall eax, esi
	test eax, eax
	jz .no_more_records
   ;jmp .next_entry

; с этой записью все, нужно перейти дальше и повторить
; на входе: esi с адресом записи, ebx с количеством оставшихся 
; на выходе: esi с адресом следующей, ebx с количеством оставшихся
.next_entry:
	; смещаемся на длину записи
	add esi, 32
	dec ebx
	jnz .parse_entry

; в этом кластере записи кончились, нужно прочитать следующий кластер
; на вершине стека лежит номер кластера, который мы только что читали.
; снимаем его, читаем следующий за ним и кладем его номер в стек
; побочные эффекты: eax, ecx, edx, вершина стека
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

; функция, которая принимает указатель на запись внутри cluster_buffer в esi
; и дописывает фрагмент LFN по нему в начало lfn_buffer. после этого она перемещает
; edi в начало записанных данных и возвращается.
; требуется: edi, указывающий на начало предыдущей записи в буфере LFN
; побочные эффекты: ecx, edi, [lfn_buffer]
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

; fasm'у что-то не нравится в записях LFN, так что макрос из lea и смещений
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

; попробовать прочитать кластер, следующий за #eax
; CF=0 -> прочитано, в буфере
; CF=1 -> это был последний кластер в цепочке
; побочные эффекты: eax, ecx, edx, dword_buffer, cluster_buffer 
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

; hexdump len байт по адресу ad
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

; перейти к байту по адресу edx:eax.
; libc-dependent: для длинных файлов будет нужен соответствующий 64-битный fseek
; побочные эффекты: eax, ecx, edx
proc long_fseek
	push 0
	push edx ; для вызова функции с аргументом в __int64 сначала push старший dword
	push eax ; потом младший
	push [fhandle]
	call [fseeki64]
	add esp, 16
	ret
	endp

; прочитать dword по оффсету из edx:eax
; побочные эффекты: eax, ecx, edx, меняется dword_buffer
proc read_dword
	call long_fseek
	cinvoke fread, dword_buffer, 4, 1, [fhandle]
	mov eax, [dword_buffer]
	ret
	endp

; прочитать кластер с номером eax
; побочные эффекты: eax, ecx, edx, dword_buffer, cluster_buffer
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
	int 3 ; тест
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


; превратить имя файла 8.3 в LFN-подобный Юникод.
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

	inc ecx ; длина названия файла
	mov esi, [short_name]
	cld
	mov edi, short_name_buffer
	rep movsb
	mov byte [edi], '.'
	inc edi ; указатель на символ за точкой
	
	mov ecx, 3
	mov esi, [short_name]
	add esi, 8 ; указатель на расширение

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

; превратить имя директории в LFN. Не проставляет точку, в отличие от convert_short_filename
proc convert_short_directory_name, short_name:DWORD
	push esi ; it's a freakin' local variable, mate
	mov esi, [short_name]
	add esi, 10
	mov ecx, 11
	std
.find_last_letter:
	dec ecx
	jz .empty ; на практике не должно случиться
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
	mov eax, edi ; вернем длину названия директории

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