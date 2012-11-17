macro __print reg,fmt,b {
      xor eax, eax
      mov reg, b
      cinvoke printf, fmt, eax
}
macro print_ubyte b { __print al,fmt_ubyte,b }
macro print_uword b { __print ax,fmt_uword,b }
macro print_dword b { cinvoke printf, fmt_udword, b }
macro storeq dst {
      mov dword [dst], eax
      mov dword [dst+4], edx
}
macro loadq src {
      mov eax, dword [src]
      mov edx, dword [src+4]
}

macro sector_to_offset sector {
      if not sector eq "eax"
	    xor eax, eax
	    mov eax, sector
      end if
      xor edx, edx
      mov dx, [bpb_head.BytesPerSec]
      mul edx
}
macro bytecopy dst,src,size {
      mov ecx, size
      if not dst eq "edi"
	    mov edi, dst
      end if
      mov esi, src
      rep movsb
}