FROM alpine:latest

# Simple hello-world validation script
RUN echo '#!/bin/sh' > /usr/local/bin/hello && \
    echo 'echo "Hello from Alpine World - Version 1.0.0"' >> /usr/local/bin/hello && \
    echo 'echo "Architecture: $(uname -m)"' >> /usr/local/bin/hello && \
    chmod +x /usr/local/bin/hello

CMD ["/usr/local/bin/hello"]
