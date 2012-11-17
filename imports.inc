library kernel32, 'kernel32.dll', \
		msvcrt,   'msvcrt.dll'
import kernel32, ExitProcess, 'ExitProcess', \
				 MultiByteToWideChar, 'MultiByteToWideChar' ; because just fuck you, that's why
import msvcrt, printf, 'printf', \
		       wprintf, 'wprintf', \
		       stricmp, 'stricmp', \
		       _mbsicmp, '_mbsicmp', \
		       _mbscmp, '_mbscmp', \
		       strtok, 'strtok', \
		       strlen, 'strlen', \
	       	   puts, 'puts',  \
	           fopen, 'fopen', \
	           _wfopen, '_wfopen', \
       		   fread, 'fread',  \
       		   fwrite, 'fwrite', \
	       	   fclose, 'fclose',  \
	       	   fseek, 'fseek',     \
	       	   fseeki64, '_fseeki64', \ 
	       	   ftell, 'ftell', \
	       	   __getmainargs, '__getmainargs'