"""Exercise the running image without external services or public certificates."""
import socket
import ssl
import sys
import time
import urllib.request

http_port, https_port, tcp_port, udp_port = map(int, sys.argv[1:])
expected = b"caddy-custom-ci"
ssl_context = ssl._create_unverified_context()  # Local CI-only internal certificate.
opener = urllib.request.build_opener(
    urllib.request.ProxyHandler({}),
    urllib.request.HTTPSHandler(context=ssl_context),
)


def check_http(port, scheme):
    # HTTPS needs a named site and matching SNI for Caddy's internal issuer.
    host = "localhost" if scheme == "https" else "127.0.0.1"
    with opener.open(f"{scheme}://{host}:{port}/", timeout=2) as response:
        assert response.status == 200
        assert response.read() == expected


def check_udp():
    message = b"caddy-custom-udp-proxy-smoke"
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.settimeout(2)
        client.sendto(message, ("127.0.0.1", udp_port))
        received, _ = client.recvfrom(4096)
        assert received == message


checks = {
    "HTTP": lambda: check_http(http_port, "http"),
    "HTTPS": lambda: check_http(https_port, "https"),
    "TCP proxy": lambda: check_http(tcp_port, "http"),
    "UDP proxy": check_udp,
}
for name, check in checks.items():
    deadline = time.monotonic() + 20
    while True:
        try:
            check()
            print(f"PASS: {name}", flush=True)
            break
        except (OSError, AssertionError) as error:
            if time.monotonic() >= deadline:
                raise RuntimeError(f"Failed: {name}") from error
            time.sleep(0.5)
