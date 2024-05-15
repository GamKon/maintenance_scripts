#!/usr/bin/env python3

import json
import os
import socket
import sys

from argparse import ArgumentParser
from contextlib import closing
from typing import Tuple, List, Set
from urllib.parse import urlparse

# 22(SSH) , 5985, 5986(WINRM), 3389(RDP) ports should be closed
DEFAULT_PORT_LIST = {22, 5985, 5986, 3389}


def main(hosts, ports) -> bool:
    total_opened_ports = 0
    print("\nBegin Testing Ports\n")
    for host in hosts:
        total_opened_ports += test_host(urlparse(host), ports)
    print("\nResults:")
    if total_opened_ports != 0:
        print(f"\n\033[31m[ FAIL ]\033[0m {total_opened_ports} opened port(s).")
        return False
    else:
        print("\n\033[32m[ PASS ]\033[0m There are no open ports.")
        return True


def test_host(host, ports) -> int:
    opened_ports = 0
    host = host.netloc if host.netloc else host.path
    for port in ports:
        if test_port(host, port):
            opened_ports += 1
    return opened_ports


def test_port(host, port) -> bool:
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as sock:
        sock.settimeout(2)  # 2 Second Timeout
        if sock.connect_ex((host, port)) == 0:
            print(f"\033[31m[ FAIL ]\033[0m {host} port {port} is\033[31m OPEN\033[0m")
            return True  # Port is open
        else:
            print(
                f"\033[32m[ PASS ]\033[0m {host} port {port} is\033[32m CLOSED\033[0m"
            )
            return False  # Port is closed


def parse_args() -> Tuple[List[str], Set[int]]:
    parser = ArgumentParser(description="Test Uri Security")
    parser.add_argument("hosts", type=str, nargs="*")
    parser.add_argument(
        "--env",
        type=str,
        default=None,
        help="Specify Environment Variable Name to read hosts to test from",
    )
    parser.add_argument(
        "--ports", type=int, nargs="+", default=None, help="Specify ports to test"
    )

    args = parser.parse_args()
    hosts = args.hosts
    # If env name provided join with cli input
    if args.env and os.environ.get(args.env):
        env_hosts = json.loads(os.environ[args.env])
        hosts = [*hosts, *env_hosts]

    if args.ports:
        ports_to_test = set(args.ports)
    else:
        ports_to_test = DEFAULT_PORT_LIST

    # Remove any duplicates from test input
    return list(set(hosts)), ports_to_test


if __name__ == "__main__":
    if not main(*parse_args()):
        sys.exit(1)
