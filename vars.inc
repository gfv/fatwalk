iteration_callback dd ?
argc dd ?
argv dd ?
penvdata dd ?
pwildcard dd ?
pstartinfo STARTUPINFO

sfilename dd ?
fhandle dd ?

bpb_head COMMON_FAT_BPB
bpb_head_size = $-bpb_head
bpb16 FAT16_BPB
bpb16_size = $-bpb16
bpb32 FAT32_BPB
bpb32_size = $-bpb32

bytes_per_cluster dd ?
file_offset dq ?
fs_type db ?

fat_offset dq ?
clusters_offset dq ?

dword_buffer dd ?
next_dir dd ?
file_cluster dd ?
file_length dd ?
align 16
short_name_buffer db 13 dup (?)
lfn_buffer db 512 dup (?)
lfn_buffer_end = $
sector_buffer db 4096 dup (?)
cluster_buffer db 32768 dup (?)
; fuck dynamic memory allocation
multibyte_buffer db 512 dup (?)
lookup_mb_buffer db 512 dup (?)