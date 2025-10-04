# Simple ARM64 HTTP Server template I used to host my html webpage

Assembled and linked with the following:

```bash
as -o server.o server.s
gcc -nostartfiles -o server server.o -lc
```

All information in 'index.html' is public already, can be found here -> https://test.lukeivan.dev/

HTML inspired by this project here -> https://github.com/owickstrom/the-monospace-web
