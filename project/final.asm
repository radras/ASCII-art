VID_SEG		equ		0b800h
START_POS	equ		3840
STR_TERM	equ		0
VID_GREEN	equ		02h
PROG_START	equ		100h

org PROG_START

;=================================================
;
; First we read information about characters
;
;=================================================

read_chardata:

	mov ah, 3Dh
	mov al, 0 						; open attribute: 0 - read-only, 1 - write-only, 2 -read&amp;write
	mov dx, chardata 				; ASCIIZ filename to open
	int 21h

	mov word [chardata_handle], ax
	jc err_loading_data
	
	mov ah, 0x3F
	mov bx, [chardata_handle] 		; handle we get when opening a file
	mov cx, [num_b_toread] 			; number of bytes to read
	mov dx, chardata_ptr 			; were to put read data
	int 21h
	
	jmp endread_chardata

err_loading_data:
	mov  ah, 9       
    mov  dx, err_msg_data  
    int  21h         

endread_chardata:
	mov ah, 3Eh
	mov bx, [chardata_handle]		; closing a file
	int 21h
	
	
;==================================================
;
; Read data from bmp file
;
;==================================================

read_bmpdata:

	mov ah, 3Dh
	mov al, 0 						; open attribute: 0 - read-only, 1 - write-only, 2 -read&amp;write
	mov dx, bmpdata 				; ASCIIZ filename to open
	int 21h

	mov word [bmpdata_handle], ax
	jc err_loading_bmp
	
	; reading header
	
	mov ah, 0x3F
	mov bx, [bmpdata_handle] 		; handle we get when opening a file	
	mov cx, 54				 		; number of bytes to read
	mov dx, bmpheader_ptr 			; were to put read data
	int 21h
	
	; offset is stored on bytes 10-13
	; we will assume that only first byte is necessary
	
	lea si, [bmpheader_ptr]
	add si, 10
	
	mov byte bl, [si]
	mov byte [bmp_offset], bl
	
	; read width
	; for now we assume it is 640px
	
	; read height
	; for now we assume it is 400px
	
	
	; now read pixels in 8x16 blocks to determine 
	; corresponding characters
	; and then print them to screen

	mov ax, VID_SEG
	mov es, ax
	mov bx, START_POS
	
	
	mov byte [i], 0
	
for25:
	cmp byte [i], 25
	je endfor25
	
	mov byte [j], 0
	.for80:
		cmp byte [j], 80
		je .endfor80
	
		mov byte [y], 0
		mov byte [accpos], 0
		mov byte [blackcnt], 0
		.fory:
			cmp byte [y], 16
			je .endfory
			mov byte [x], 0
			.forx:
				cmp byte [x], 8
				je .endforx
				
				pusha
				
				; calculate height of pointer
				mov bl, 16
				mov byte al, [i] 
				mul bl
				mov bh, 0
				mov byte bl, [y]
				add ax, 15
				sub ax, bx
				mov word [h], ax 
			
				; calculate width of pointer
				
				mov bl, 8
				mov byte al, [j] 
				mul bl
				mov bh, 0
				mov byte bl, [x]
				add ax, bx  
				mov word [w], ax 
				
				; calculate pointer position
				; first move by bmp_offset from start of the file
				
				mov ah, 42h
				mov al, 0
				mov bx, [bmpdata_handle]
				mov cx, 0
				mov dh, 0
				mov byte dl, 54 					;[bmp_offset]
				int 21h
				
				jc err_moving_ptr
							
				; second move by h*640*3
				mov word bx, [h]
				mov ax, 1920
				mul bx
				
				mov cx, dx
				mov dx, ax
				mov ah, 42h
				mov al, 1
				mov bx, [bmpdata_handle]
				int 21h
				
				jc err_moving_ptr
				
				; third move by 3*w

				mov word bx, [w]
				mov ax, 3
				mul bx
				
				mov cx, dx
				mov dx, ax
				mov ah, 42h
				mov al, 1
				mov bx, [bmpdata_handle]
				int 21h
	
				jc err_moving_ptr
	
				; here we read the byte for pixel
				
				mov ah, 0x3F
				mov bx, [bmpdata_handle] 		; handle we get when opening a file
				mov cx, 1				 		; number of bytes to read
				mov dx, pixel  					; were to put read data
				int 21h
				
				; iterate through charaters and change accumulator
			
				mov di, accumulator
				mov si, chardata_ptr
				mov byte bl, [accpos]
				mov bh, 0
				add si, bx
				
				mov word [k], 0
				.forchar:
					cmp word [k], 256
					je .endforchar
					
					mov byte bl, [si]
					mov byte al, [pixel]
					cmp byte al, bl
					je .continueforchar
					
					inc byte [di]
					
					.continueforchar:
					
					cmp byte al, 0
					jne .newcontinue
					
					inc byte [blackcnt]
					
					.newcontinue:
					
					add word si, 128
					inc word [k]
					inc di
					jmp .forchar
				.endforchar:
				
				popa
				
				inc byte [x]
				inc byte [accpos]
				jmp .forx
			.endforx:
			inc byte [y]
			;mov ah, 9
			;mov dx, delim2
			;int 21h
			jmp .fory
		.endfory:
	
		.printchar:
		
		pusha
		
		;mov ah, 9
		;mov dx, accumulator
		;int 21h
		
		mov byte [minpos], 0
		mov byte [mindiff], 128
		;mov si, accumulator
		lea si, [accumulator]
		
		mov word [k], 0
		.forcharprint:
			cmp word [k], 256
			je .endforcharprint
					
			mov byte bl, [si] 			; accumulator	
			mov byte al, [mindiff]		; minimal difference
			
			mov ah, 0
			mov bh, 0
			cmp ax, bx
			jl .continueacc
			
			mov byte bl, [si]
			mov byte [mindiff], bl
			mov word bx, [k]
			mov byte [minpos], bl
			
			.continueacc:
			
			mov byte [si], 0
			inc si
			inc word [k]
			jmp .forcharprint
		.endforcharprint:
	
		popa
		
		cmp byte [mindiff], 32
		jl .standardreplace
		
		cmp byte [blackcnt], 64
		jg .next1
		
		mov byte [minpos], 176
		jmp .standardreplace
		
		.next1:
		
		cmp byte [blackcnt], 98
		jg .next1
		
		mov byte [minpos], 177
		jmp .standardreplace
		
		.next2:

		mov byte [minpos], 178

		.standardreplace:
		mov byte al, [minpos]
		mov byte [es:bx], al
		inc bx
		mov byte [es:bx], VID_GREEN
		inc bx
			
	
		inc byte [j]
		jmp .for80
	.endfor80:
	inc byte [i]
	sub bx, 320
	jmp for25
	
endfor25:

	jmp endread_bmpdata	
	
;------------------------------------------
;  Error handling
;------------------------------------------
	
err_loading_bmp:
	mov  ah, 9       
    mov  dx, err_msg_bmp  
    int  21h
	jmp ending

err_moving_ptr:
	mov  ah, 9       
    mov  dx, err_msg_ptr  
    int  21h
	jmp ending
	
endread_bmpdata:
	mov ah, 3Eh
	mov bx, [bmpdata_handle]		; closing a file
	int 21h


ending:	
	ret;
	

chardata:	 		db "data.txt", 0
num_b_toread: 		dw 32768
chardata_handle: 	dw 0
err_msg_data:		db 'Error! Character data are not stored.', 0Ah, '$'
chardata_ptr: 		resb 32768

bmpdata:	 		db "tesla1.bmp", 0
num_b_toread_bmp: 	dw 128
bmpdata_handle: 	dw 0
err_msg_bmp:		db 'Error! BMP file is not opened.', 0Ah, '$'
bmpdata_ptr: 		resb 128

bmpheader_ptr:		resb 54
bmp_offset:			resb 1

bmp_width:			dw 640
bmp_height:			dw 400

debug:				db 'DEBUG', '$'
err_msg_ptr:		db 'Error occured while moving file pointer!', 0Ah, '$'

pixel:				db 0, '$'

h:					dw 0, '$'
w:					dw 0, '$'
i:					db 0
j:					db 0
x:					db 0
y:					db 0
k:					dw 0
delim1:				db '$'
accumulator:		resb 256
delim2: 			db 0Ah, '$'
accpos:				db 0, '$'
minpos:				db 0
mindiff:			db 128, '$'
blackcnt:			db 0