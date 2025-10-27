# Simple ARM64 HTTP Server template I used to host my html webpage

Should work on ARM64 CPUs running linux, haven't attempted it on apple silicon yet. probably doesn't work with all the syscalls

Assembled and linked with the following:

```bash
as -o server.o server.s
gcc -nostartfiles -o server server.o -lc
```

All information in 'index.html' is public already, can be found here -> https://lukeivan.dev/

HTML inspired by this project here -> https://github.com/owickstrom/the-monospace-web
