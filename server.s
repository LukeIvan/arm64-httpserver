.section .rodata
start_msg: .asciz "Server starting on port 8080...\n"
bind_msg: .asciz "Bind syscall successful...\n"
listen_msg: .asciz "Listen syscall successful...\n"
wait_msg: .asciz "Retrying...\n"
socket_error: .asciz "Socket creation failed!\n"
bind_error: .asciz "Bind failed!\n"
listen_error: .asciz "Failed to listen\n"
http_200: .ascii "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: "
http_200_len = . - http_200
http_404: .ascii "HTTP/1.1 404 Not Found\r\n\r\nContent-Type: text/html\r\nContent-Length: 13\r\n\r\n404 Not Found"
http_404_len = . - http_404
http_end: .ascii "\r\n\r\n"
request_error_msg: .asciz "Error handling request - too long or unknown request"
re_len = . - request_error_msg
file_error_msg: .asciz "Error handling file index.html"
http_200_info: .asciz "Received: GET - 200 OK\n"
http_200_info_len = . - http_200_info
http_404_info: .asciz "Received: GET - 404 Not Found\n"
http_404_info_len = . - http_404_info
fe_len = . - file_error_msg
// ^^ only dealing with one file here

fmt: .asciz "%ld"
get_root: .asciz "GET /"
get_index: .asciz "GET /index.html"
index_filename: .asciz "index.html"

.section .data
sockaddr:
    .hword 2                          // AF_INET
    .hword 0x901F                     // port 8080 in network byte order (LITTLE ENDIAN REMEMBER THIS IMPORTANT)
    .word 0                           // INADDR_ANY (0.0.0.0)
    .space 8                          // padding to 16 bytes

timespec:
    .quad 3     // tv_sec: 3 seconds
    .quad 0 

// Buffers for HTTP handling
request_buffer: .space 2048        // Buffer for HTTP request
file_buffer: .space 32768          // Buffer for file content (32KB)
.equ file_buffer_size, 32768
content_length_str: .space 16, 0  // String buffer for content length
.equ request_buffer_size, 2048
.equ AT_FDCWD, -100

.section .text
.global _start
.equ HTTP_PORT, 8080
.equ OPENAT_FLAGS, 0

exit:
    mov x8, #93                     // sys_exit
    svc #0

_start:
    mov x0, #1                      // stdout fd
    ldr x1, =start_msg
    mov x2, #32                     // length of message
    mov x8, #64                     // sys_write
    svc #0

    mov x20, #3                     // retry counter (3 attempts)
create_loop:
    // Create socket
    mov x0, #2                      // AF_INET (IPv4)
    mov x1, #1                      // SOCK_STREAM (TCP)
    mov x2, #0                      // TCP
    mov x8, #198                    // sys_socket
    svc #0
    mov x19, x0                     // save socket fd in x19
    
    cmp x0, #0
    b.lt socket_failed

    mov x20, #3                     // retry counter (3 attempts)
bind_loop:
    mov x0, x19                     
    ldr x1, =sockaddr               // sockaddr struct
    mov x2, #16                     // sockaddr = 16 bytes
    mov x8, #200                    // syscall for bind
    svc #0
    
    // Check if bind failed (return value < 0)
    cmp x0, #0
    b.lt bind_failed
    mov x0, #1

    ldr x1, =bind_msg
    mov x2, #27                    // length of message
    mov x8, #64
    svc #0

listen_loop:
    mov x0, x19                     // socket fd
    mov x1, #32                     // # items in backlog
    mov x8, #201                    // syscall for listen
    svc #0
    
    // Check if listen failed
    cmp x0, #0
    b.lt listen_failed

    mov x0, #1
    ldr x1, =listen_msg
    mov x2, #29                    // length of message
    mov x8, #64
    svc #0

accept_loop:
    mov x0, x19                     // socket fd
    mov x1, #0                      // client address (NULL)
    mov x2, #0                      // address length (NULL)
    mov x8, #202                    // sys_accept
    svc #0
    mov x20, x0                     // save client fd in x20
    
    // Check if accept failed
    cmp x0, #0
    b.lt accept_failed
    
    // Handle HTTP request
    bl handle_request
    
    // Close the client connection
    mov x0, x20                     // client fd
    mov x8, #57                     // sys_close
    svc #0
    
    // Loop back to accept more connections
    b accept_loop

    // Exit
    mov x0, #0                      // status
    bl exit

handle_request:
    stp x29, x30, [sp, #-16]!      // Save frame pointer and link register
    mov x29, sp

    mov x0, x20                     // client fd
    ldr x1, =request_buffer         // buffer to read into
    mov x2, request_buffer_size     // length shouldn't be more than 1024. I think
    mov x8, #63                     // sys_read
    svc #0
    mov x21, x0                     // actual bytes read

    // DEBUGGING FOR CLOUDFLARE
    mov x0, #1              // stdout fd
    ldr x1, =request_buffer  // buffer pointer
    mov x2, x21             // bytes read
    mov x8, #64             // sys_write
    svc #0

    //cmp x0, #0
    //b.le request_error              // if <=0, error

    cmp x21, #request_buffer_size   // if exceeds buffer size, error out
    b.ge request_error

    ldr x0, =request_buffer        // pointer to request
    ldr x1, =get_root              // "GET /"
    mov x2, #5                     // length of "GET /"
    mov x3, x21
    bl strcmp                      // check if request is for root
    cmp x0, #0
    b.eq handle_root
    
    ldr x0, =request_buffer
    ldr x1, =get_index             // "GET /index.html"
    mov x2, #15                    // length of "GET /index.html"
    bl strcmp                     // check if request is for index.html
    cmp x0, #0
    b.eq handle_root

    mov x0, x20                    // client fd
    ldr x1, =http_404              // 404 response
    mov x2, #http_404_len          // length of 404 response using assembler directives this time and not hardcoded
    mov x8, #64                    // sys_write
    svc #0

    mov x0, #1                      // stdout
    ldr x1, =http_404_info          
    mov x2, #http_404_info_len      // length of message
    mov x8, #64
    svc #0

    mov x0, #1
    b request_done

handle_root:
    mov x0, AT_FDCWD                // man 2 openat -> pathname is interpreted relative to cwd
    ldr x1, =index_filename         // raw HTML. I'm not a webdev.
    mov x2, OPENAT_FLAGS
    mov x8, #56                     // sys_openat
    svc #0

    cmp x0, #0                      // branch if x0 < 0 (error)
    b.lt file_error

    mov x21, x0                     // save file fd in x21

    mov x0, x21                     // file fd
    ldr x1, =file_buffer
    mov x2, file_buffer_size        // buffer size
    mov x8, #63                     // sys_read
    svc #0
    
    cmp x0, #0
    b.le file_error
    
    mov x22, x0                     // save file size in x22
    
    // Convert file size to string. using snprintf cause laziness and this is already like 400 lines
    ldr x0, =content_length_str
    mov x1, #16
    ldr x2, =fmt
    mov x3, x22
    bl snprintf
    mov x23, x0                     // save content length in x23

    // --- convert file size into content_length_str with snprintf (unchanged) ---
    ldr x0, =content_length_str
    mov x1, #16
    ldr x2, =fmt
    mov x3, x22
    bl snprintf

    mov x0, x20                     // client fd
    ldr x1, =http_200               // "HTTP/1.1 200 OK"
    mov x2, #http_200_len           // length of http_200
    mov x8, #64                     // sys_write
    svc #0

    mov x0, x20                     // client fd
    ldr x1, =content_length_str     // content length string
    mov x2, x23                     // length of content length string
    mov x8, #64
    svc #0
    
    mov x0, x20
    ldr x1, =http_end               // "\r\n\r\n"
    mov x2, #4                      // length of http_end
    mov x8, #64
    svc #0

    mov x0, x20
    ldr x1, =file_buffer            // index.html
    mov x2, x22                     // file size
    mov x8, #64                     // sys_write
    svc #0

    mov x0, x21                     // file fd
    mov x8, #57                     // sys_close
    svc #0

    mov x0, #1                      // stdout
    ldr x1, =http_200_info          
    mov x2, #http_200_info_len      // length of message
    mov x8, #64
    svc #0

    b request_done

request_error:
    mov x0, #2                       // stderr
    ldr x1, =request_error_msg
    mov x2, #re_len
    mov x8, #64
    svc #0

    mov x0, x20                    // client fd
    ldr x1, =http_404              // 404 response
    mov x2, #http_404_len          
    mov x8, #64                    // sys_write
    svc #0

    b request_done

file_error:
   mov x0, #2                       // stderr
   ldr x1, =file_error_msg
   mov x2, #fe_len
   mov x8, #64
   svc #0

   mov x0, x20                    // client fd
   ldr x1, =http_404              // 404 response
   mov x2, #http_404_len          
   mov x8, #64                    // sys_write
   svc #0

   b request_done  

request_done:
    ldp x29, x30, [sp], #16
    ret

strcmp:
    mov x3, #0                      // char counter

strcmp_loop:
    cmp x3, x2                      // check if we've compared n chars
    b.ge strcmp_equal_for_length

    ldrb w4, [x0, x3]               // x0 -> pointer to request, x3 char counter. No indexing, loads the byte pointed to from address x0 plus x3 offset
    ldrb w5, [x1, x3]               // x1 -> pointer to "GET /", x3 char counter
    
    cmp w4, w5                      // comparison result
    b.ne strcmp_diff                // if not equal, return 1

    add x3, x3, #1                  // increment char counter
    b strcmp_loop

strcmp_equal_for_length:
    ldrb w4, [x0, x2]		        // next character in request buffer
    cmp w4, #' '                    // space before specifying HTTP Protocol, ex GET /index.html HTTP/1.1
    b.eq strcmp_end
    cmp w4, #'\r'
    b.eq strcmp_end
    cmp w4, #0
    b.eq strcmp_end
    b strcmp_diff

strcmp_end:
    mov x0, #0
    ret

strcmp_diff:
    mov x0, #1
    ret

socket_failed:
    mov x0, #1                      // stdout
    ldr x1, =wait_msg
    mov x2, #12
    mov x8, #64
    svc #0                          // output retry
    
    mov x8, #101                    // sys_nanosleep
    ldr x0, =timespec               // point to timespec struct (3 secs)
    mov x1, #0
    svc #0

    sub x20, x20, #1                // decrement retry counter
    cmp x20, #0                     // check if retries exhausted
    b.ge create_loop                // branch if < 3 tries

    mov x0, #2                      // stderr
    ldr x1, =socket_error           // error message
    mov x2, #27
    mov x8, #64                     // sys_write

    svc #0
    mov x0, #1                      // exit status 1
    bl exit                        // call exit subroutine

bind_failed:
    mov x0, #1                      // stdout
    ldr x1, =wait_msg
    mov x2, #12
    mov x8, #64
    svc #0                          // output retry

    mov x8, #101                    // sys_nanosleep
    ldr x0, =timespec               // point to timespec struct (3 secs)
    mov x1, #0
    svc #0

    sub x20, x20, #1
    cmp x20, #0
    b.ge bind_loop

    mov x0, #2                      // stderr
    ldr x1, =bind_error             // error message
    mov x2, #16                     // length of message
    mov x8, #64                     // sys_write
    svc #0

listen_failed:
    mov x0, #2                      // stderr
    ldr x1, =listen_error           // error message (reuse for now)
    mov x2, #15
    mov x8, #64                     // sys_write
    svc #0
    mov x0, #3                      // exit status 3
    bl exit                         // call exit subroutine

accept_failed:
    mov x0, #2                      // stderr
    ldr x1, =listen_error           // error message (reuse for now)
    mov x2, #15
    mov x8, #64                     // sys_write
    svc #0
    mov x0, #4                      // exit status 4
    bl exit                         // call exit subroutine
