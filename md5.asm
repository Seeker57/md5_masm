 .686 ; Тип процессора
 .model flat, stdcall ; Модель памяти и стиль вызова подпрограмм
 option casemap: none ; Чувствительность к регистру
 ; --- Подключение файлов с кодом, макросами, константами, прототипами функций и т.д.
 include C:\masm32\include\windows.inc
 include C:\masm32\include\kernel32.inc
 include C:\masm32\include\user32.inc
 include C:\masm32\include\msvcrt.inc
 ; --- Подключаемые библиотеки ---
 includelib C:\masm32\lib\user32.lib
 includelib C:\masm32\lib\kernel32.lib
 includelib C:\masm32\lib\msvcrt.lib

 ; --- Сегмент данных ---
.data
	begin_input db 1024 dup(?)		; входная последовательность
	hash db 16 dup(0)			; значение md5-хеша
	hash_char db "0123456789abcdef", 0	; строка для символьного представления хеша
	final_hash_char db 33 dup(0)		; символьное представление хеша

	; переменные буфера, где будут храниться рез-ты промежуточных вычислений
	buffer_A dd 01234567h
	buffer_B dd 89abcdefh
	buffer_C dd 0fedcba98h
	buffer_D dd 76543210h

	; константы для повышения криптостойкости
	t_const dd 0d76aa478h, 0e8c7b756h, 0242070dbh, 0c1bdceeeh, 0f57c0fafh, 04787c62ah, 0a8304613h, 0fd469501h
    	  	dd 0698098d8h, 08b44f7afh, 0ffff5bb1h, 0895cd7beh, 06b901122h, 0fd987193h, 0a679438eh, 049b40821h
    	  	dd 0f61e2562h, 0c040b340h, 0265e5a51h, 0e9b6c7aah, 0d62f105dh, 002441453h, 0d8a1e681h, 0e7d3fbc8h
    	  	dd 021e1cde6h, 0c33707d6h, 0f4d50d87h, 0455a14edh, 0a9e3e905h, 0fcefa3f8h, 0676f02d9h, 08d2a4c8ah
    	  	dd 0fffa3942h, 08771f681h, 06d9d6122h, 0fde5380ch, 0a4beea44h, 04bdecfa9h, 0f6bb4b60h, 0bebfbc70h
    	  	dd 0289b7ec6h, 0eaa127fah, 0d4ef3085h, 004881d05h, 0d9d4d039h, 0e6db99e5h, 01fa27cf8h, 0c4ac5665h
    	  	dd 0f4292244h, 0432aff97h, 0ab9423a7h, 0fc93a039h, 0655b59c3h, 08f0ccc92h, 0ffeff47dh, 085845dd1h
    	  	dd 06fa87e4fh, 0fe2ce6e0h, 0a3014314h, 04e0811a1h, 0f7537e82h, 0bd3af235h, 02ad7d2bbh, 0eb86d391h
	
.code

; Инициализирующая функция
DllMain proc hlnstDLL:DWORD, reason:DWORD, unused:DWORD
	mov EAX, 1 
	ret
DllMain Endp

; макрос для передачи аргументов ф-ции round в одну строчку (для уменьшения объема строк)
@ MACRO p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10
	p0
	p1
	p2
	p3
	p4
	p5
	p6
	p7
	p8
	p9
	p10
	ENDM

; F(x, y, z) = (x & y) | (~x & z)
F proc x:DWORD, y:DWORD, z:DWORD

	push ebx
	push ecx

	mov eax, x
	mov ebx, y
	and eax, ebx

	mov ebx, x
	not ebx
	mov ecx, z
	and ebx, ecx
	
	or eax, ebx

	pop ecx
	pop ebx
	ret 12
F endp

; G(x, y, z) = (x & z) | (~z & y)
G proc x:DWORD, y:DWORD, z:DWORD

	push ebx
	push ecx

	mov eax, x
	mov ebx, z
	and eax, ebx

	mov ebx, z
	not ebx
	mov ecx, y
	and ebx, ecx
	
	or eax, ebx

	pop ecx
	pop ebx
	ret 12
G endp

; H(x, y, z) = x ^ y ^ z
H proc x:DWORD, y:DWORD, z:DWORD

	push ebx

	mov eax, x
	mov ebx, y
	xor eax, ebx
	mov ebx, z
	xor eax, ebx

	pop ebx
	ret 12
H endp

; I(x, y, z) = y ^ (~z | x)
I proc x:DWORD, y:DWORD, z:DWORD

	push ebx
	
	mov eax, z
	not eax
	mov ebx, x
	or eax, ebx
	mov ebx, y
	xor eax, ebx

	pop ebx
	ret 12
I endp

; подпрограмма для добавления битов в исходную последовательность
append_bits proc input:DWORD, lenght:DWORD
	
	push edi
	push edx
	push ecx

	mov edi, input
	mov eax, lenght					; eax = новая длина последовательности
	mov byte ptr [edi + eax], 80h			; помещаем единичный бит в конец последовательности
	inc eax

	j_loop1:
		push eax
		mov edx, eax
		mov ecx, 64
		cdq
		div ecx
		pop eax
	
		; если длина новой последовательности % 64 != 56, то добавляем нулевой байт в конец
		cmp edx, 56
		jne j_add_zero_byte
		jmp j_loop1_out

		j_add_zero_byte:
			mov byte ptr [edi + eax], 00h
			inc eax
			jmp j_loop1
	j_loop1_out:
		
		mov ecx, lenght
		imul ecx, 8			; длина первоначальной последовательности в битах

		; добавляем эту длину в конец последовательности в виде 64-битной последовательности
		mov dword ptr [edi + eax], 00000000h
		add eax, 4
		mov dword ptr [edi + eax], 00000000h
		add eax, 3
		mov byte ptr [edi + eax], cl
		inc eax
	
		pop ecx
		pop edx
		pop edi
		ret 8

append_bits endp

; ф-ция вызывающая обработку для каждого 512-битного блока входной последовательности
process proc start_pos:DWORD

	push edi

	mov edi, start_pos
	j_loop2:
		cmp byte ptr [edi], 0
		jne j_next_block
		jmp j_loop2_out

	j_next_block:
		push edi
		call process_block
		add edi, 64
		jmp j_loop2

	j_loop2_out:
		pop edi
		ret 4		

process endp

;раунд обработки 32-битного блока с использованием одной из функций: F, G, H, I
round proc a:DWORD, b:DWORD, c_:DWORD, d:DWORD, k:DWORD, s:DWORD, i:DWORD, func:DWORD, block:DWORD
	
	push eax
	push ecx
	push ebx

	; eax = func(b, c, d) - одна из ф-ций F, G, H, I
	mov eax, dword ptr [d]
	push dword ptr [eax]
	mov eax, dword ptr [c_]
	push dword ptr [eax]
	mov eax, dword ptr [b]
	push dword ptr [eax]
	call func

	; a += func(b, c, d) + block[k] + t[i]
	mov ecx, k
	mov ebx, dword ptr [block]
	movzx ebx, byte ptr [ebx + ecx]
	add eax, ebx
	mov ecx, i
	mov ebx, dword ptr [t_const + ecx]
	add eax, ebx
	mov ecx, dword ptr [a]
	add dword ptr [ecx], eax
	
	; a = a << s
	mov cl, byte ptr s
	mov eax, dword ptr [a]
	mov eax, dword ptr [eax]
	rol eax, cl
	mov ecx, dword ptr [a]
	mov dword ptr [ecx], eax

	; a += b
	mov ecx, dword ptr [b]
	mov ebx, dword ptr [ecx]
	mov ecx, dword ptr [a]
	add dword ptr [ecx], ebx

	pop ebx
	pop ecx
	pop eax
	ret 36
	
round endp

; функция для обработки 512-битного блока входной последовательности
process_block proc current_block:DWORD

	; сохраняем значения буферов
	push buffer_A
	push buffer_B
	push buffer_C
	push buffer_D

	; 512-битный блок разделяется на 16 32-битных блока по 4 раунда в каждом

	@<push current_block>, <push offset F>, <push 1>, <push 7>, <push 0>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset F>, <push 2>, <push 12>, <push 1>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset F>, <push 3>, <push 17>, <push 2>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset F>, <push 4>, <push 22>, <push 3>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset F>, <push 5>, <push 7>, <push 4>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset F>, <push 6>, <push 12>, <push 5>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset F>, <push 7>, <push 17>, <push 6>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset F>, <push 8>, <push 22>, <push 7>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset F>, <push 9>, <push 7>, <push 8>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset F>, <push 10>, <push 12>, <push 9>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset F>, <push 11>, <push 17>, <push 10>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset F>, <push 12>, <push 22>, <push 11>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset F>, <push 13>, <push 7>, <push 12>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset F>, <push 14>, <push 12>, <push 13>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset F>, <push 15>, <push 17>, <push 14>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset F>, <push 16>, <push 22>, <push 15>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset G>, <push 17>, <push 5>, <push 1>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset G>, <push 18>, <push 9>, <push 6>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset G>, <push 19>, <push 14>, <push 11>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset G>, <push 20>, <push 20>, <push 0>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset G>, <push 21>, <push 5>, <push 5>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset G>, <push 22>, <push 9>, <push 10>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset G>, <push 23>, <push 14>, <push 15>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset G>, <push 24>, <push 20>, <push 4>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset G>, <push 25>, <push 5>, <push 9>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset G>, <push 26>, <push 9>, <push 14>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset G>, <push 27>, <push 14>, <push 3>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset G>, <push 28>, <push 20>, <push 8>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset G>, <push 29>, <push 5>, <push 13>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset G>, <push 30>, <push 9>, <push 2>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset G>, <push 31>, <push 14>, <push 7>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset G>, <push 32>, <push 20>, <push 12>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset H>, <push 33>, <push 4>, <push 5>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset H>, <push 34>, <push 11>, <push 8>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset H>, <push 35>, <push 16>, <push 11>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset H>, <push 36>, <push 23>, <push 14>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset H>, <push 37>, <push 4>, <push 1>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset H>, <push 38>, <push 11>, <push 4>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset H>, <push 39>, <push 16>, <push 7>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset H>, <push 40>, <push 23>, <push 10>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset H>, <push 41>, <push 4>, <push 13>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset H>, <push 42>, <push 11>, <push 0>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset H>, <push 43>, <push 16>, <push 3>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset H>, <push 44>, <push 23>, <push 6>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset H>, <push 45>, <push 4>, <push 9>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset H>, <push 46>, <push 11>, <push 12>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset H>, <push 47>, <push 16>, <push 15>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset H>, <push 48>, <push 23>, <push 2>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset I>, <push 49>, <push 6>, <push 0>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset I>, <push 50>, <push 10>, <push 7>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset I>, <push 51>, <push 15>, <push 14>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset I>, <push 52>, <push 21>, <push 5>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset I>, <push 53>, <push 6>, <push 12>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset I>, <push 54>, <push 10>, <push 3>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset I>, <push 55>, <push 15>, <push 10>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset I>, <push 56>, <push 21>, <push 1>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset I>, <push 57>, <push 6>, <push 8>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset I>, <push 58>, <push 10>, <push 15>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset I>, <push 59>, <push 15>, <push 6>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset I>, <push 60>, <push 21>, <push 13>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	@<push current_block>, <push offset I>, <push 61>, <push 6>, <push 4>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <call round>
	@<push current_block>, <push offset I>, <push 62>, <push 10>, <push 11>, <push offset buffer_C>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <call round>
	@<push current_block>, <push offset I>, <push 63>, <push 15>, <push 2>, <push offset buffer_B>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <call round>
	@<push current_block>, <push offset I>, <push 64>, <push 21>, <push 9>, <push offset buffer_A>, <push offset buffer_D>, <push offset buffer_C>, <push offset buffer_B>, <call round>

	; добавляем к измененным значениям буфера их значения до начала всех раундов
	pop eax
	add buffer_D, eax
	pop eax
	add buffer_C, eax
	pop eax
	add buffer_B, eax
	pop eax
	add buffer_A, eax

	ret 4
process_block endp

; получение значения хеша md5
get_hash proc
	
	push eax

	; значение хеша - это 128-битная последовательность из 4-х переменных буфера
	mov eax, buffer_A
	mov dword ptr hash, eax
	mov eax, buffer_B
	mov dword ptr [hash + 4], eax
	mov eax, buffer_C
	mov dword ptr [hash + 8], eax
	mov eax, buffer_D
	mov dword ptr [hash + 12], eax

	pop eax
	ret

get_hash endp

; функция для получения символьного хеша
get_char_hash proc

	push ecx
	push esi
	push edi

	mov ecx, 16			; счетчик цикла
	xor esi, esi			; i = 0
	
	j_loop3:
		movzx eax, byte ptr [hash + esi]			; eax = hash[i]
		shr eax, 4						; eax = hash[i] >> 4
		mov al, byte ptr [hash_char + eax]
		mov byte ptr [final_hash_char + esi*2], al		; edi[i] = hash_char[eax]
		movzx eax, byte ptr [hash + esi]			; eax = hash[i]
		and eax, 0fh						; eax = hash[i] & 0fh
		mov al, byte ptr [hash_char + eax]
		mov byte ptr [final_hash_char + esi*2 + 1], al		; edi[i] = hash_char[eax]
		inc esi
		loop j_loop3
	
	mov byte ptr [final_hash_char + esi*2], 0	; добавляем в конец строки ноль символ
	
	pop edi
	pop esi
	pop ecx
	ret

get_char_hash endp

; общая функция шифрования по методу md5
md5 proc stdcall message:DWORD, lenght:DWORD

	push ecx
	push edx
	push esi

	mov ecx, lenght
	xor esi, esi
	mov edx, dword ptr [message]
	j_loop4:
		mov al, byte ptr [edx + esi]
		mov byte ptr [begin_input + esi], al
		inc esi
		loop j_loop4
	
	push lenght
	push offset begin_input
	call append_bits

	push offset begin_input
	call process

	call get_hash
	call get_char_hash

	mov eax, offset final_hash_char

	pop esi
	pop edx
	pop ecx
	ret

md5 endp

END DllMain