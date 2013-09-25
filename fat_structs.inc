struc COMMON_FAT_BPB {
       .jmpBoot db 3 dup (?)
       .OEMName db 8 dup (?)
       .BytesPerSec dw ?
       .SecPerClus db ?
       .RsvdSecCnt dw ?
       .NumFATs db ?
       .RootEntCnt dw ?
       .TotSec16 dw ?
       .Media db ?
       .FATSz16 dw ?
       .SecPerTrk dw ?
       .NumHeads dw ?
       .HiddSec dd ?
       .TotSec32 dd ?
}

struc FAT16_BPB {
      .DrvNum db ?
      .Reserved1 db ?
      .BootSig db ?
      .VolID dd ?
      .VolLab db 11 dup (?)
      .FilSysType db 8 dup (?)
}

struc FAT32_BPB {
      .FATSz32 dd ?
      .ExtFlags dw ?
      .FSVer dw ?
      .RootClus dd ?
      .FSInfo dw ?
      .BkBootSec dw ?
      .Reserved db 12 dup (?)
      .DrvNum db ?
      .Reserved1 db ?
      .BootSig db ?
      .VolID dd ?
      .VolLab db 11 dup (?)
      .FilSysType db 8 dup (?)
}

struc FAT32_dirent {
      .Name db 8 dup (?)
      .Extension db 3 dup (?)
      .Attribute db ?
      .Case db ?
      .ctime_ms db ?
      .ctime dw ?
      .cdate dw ?
      .adate dw ?
      .StartClusterHigh dw ?
      .Timestamp dw ?
      .Datestamp dw ?
      .StartCluster dw ?
      .Size dd ?
}

struc LFN_dirent {
      .Sequence db ?
      .P1 db 10 dup (?) ; юникод, чуваки, тут всего 5 симолов
      .Attribute db ?
      .Reserved db ?
      .Checksum db ?
      .P2 db 12 dup (?)
      .StartCluster dw ?
      .P3 db 4 dup (?)
}

ATTR_RO = 0x01
ATTR_HID = 0x02
ATTR_SYS = 0x04
ATTR_VL = 0x08
ATTR_DIR = 0x10
ATTR_ARC = 0x20