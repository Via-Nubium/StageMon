#!/usr/bin/env python3
# Listens for OSC messages on UDP port 10024 and prints them.
# Install dependency: pip install python-osc

from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer

PORT = 10024

def handle_message(address, *args):
    print(f"{address}  ->  {list(args)}")

dispatcher = Dispatcher()
dispatcher.set_default_handler(handle_message)

server = BlockingOSCUDPServer(("0.0.0.0", PORT), dispatcher)
print(f"Escuchando en puerto {PORT}... (Ctrl+C para salir)")
server.serve_forever()
