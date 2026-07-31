#!/usr/bin/env python3
"""
XR18 OSC Simulator
Simulates a Behringer XR18 mixer console for testing the StageMon Flutter app.
No external dependencies required — uses only Python standard library.

Usage:
    python xr18_simulator.py [--port PORT]

Interactive commands (type after the '> ' prompt):
    state [bus]                  Show fader/mute state for a bus (default: 1)
    set <addr> <val>             Set any OSC address and push to connected app
    link <1|2|3> <0|1>          Toggle stereo bus pairing (1→1-2, 2→3-4, 3→5-6)
    name <ch> <name>             Set a channel name (ch = 1-16)
    mute aux <bus> <0|1>         Set AUX bus on/off (/bus/{bus}/mix/on) (0=muted, 1=unmuted)
    lr                           Show Main LR fader and mute state
    lr fader <0.0-1.0>           Set Main LR fader level and push
    lr mute <0|1>                Set Main LR mute (0=muted, 1=unmuted) and push
    meters [on|off]              Show/toggle VU meter simulation (sends /meters/1 at ~10 Hz)
    snap                         List all snapshots
    snap load <N>                Load snapshot N and push /-snap/index to connected app
    snap name <N> <name>         Set snapshot name
    clients                      List registered /xremote clients
    q / quit                     Exit
"""

import math
import socket
import struct
import threading
import time
import argparse
from typing import Any, Dict, List, Tuple

PORT = 10024
FIRMWARE = "1.18-sim"
DEFAULT_MODEL = "XR18"
XREMOTE_TTL = 10.0   # seconds before /xremote registration expires
METER_TTL   = 15.0   # seconds before /meters subscription expires
METER_INTERVAL = 0.1 # seconds between /meters/1 pushes (~10 Hz)

# ── OSC codec ─────────────────────────────────────────────────────────────────

def _pad4(data: bytes) -> bytes:
    rem = len(data) % 4
    return data + b'\x00' * (4 - rem) if rem else data

def _osc_str(s: str) -> bytes:
    return _pad4(s.encode('utf-8') + b'\x00')

def osc_build(address: str, *args: Any) -> bytes:
    tags = ','
    payload = b''
    for a in args:
        if isinstance(a, bool):          # bool is subclass of int, check first
            tags += 'T' if a else 'F'
        elif isinstance(a, float):
            tags += 'f'
            payload += struct.pack('>f', a)
        elif isinstance(a, int):
            tags += 'i'
            payload += struct.pack('>i', a)
        elif isinstance(a, str):
            tags += 's'
            payload += _osc_str(a)
        elif isinstance(a, (bytes, bytearray)):
            tags += 'b'
            payload += struct.pack('>i', len(a)) + _pad4(bytes(a))
    return _osc_str(address) + _osc_str(tags) + payload


# Must match osc_service.dart noiseFloor constant.
# Values below this map to 0.0 in the app; 0 = 0 dBFS.
METER_NOISE_FLOOR = -16384


def build_meter_blob(values: List[int]) -> bytes:
    """Build /meters/1 blob: 4-byte LE int32 count + N × 2-byte LE int16.
    XR18 encoding: -32768 = silence, 0 = 0 dBFS."""
    data = struct.pack('<i', len(values))
    for v in values:
        data += struct.pack('<h', max(-32768, min(0, v)))
    return data


def _signal_to_int16(level: float) -> int:
    """Map signal level [0.0, 1.0] to XR18 int16 [NOISE_FLOOR, 0]."""
    return int(level * (-METER_NOISE_FLOOR)) + METER_NOISE_FLOOR

def _read_str(data: bytes, pos: int) -> Tuple[str, int]:
    null = data.index(b'\x00', pos)
    s = data[pos:null].decode('utf-8', errors='replace')
    # advance to next 4-byte boundary after the null byte
    padded = ((null - pos + 4) // 4) * 4
    return s, pos + padded

def osc_parse(data: bytes) -> Tuple[str, List[Any]]:
    try:
        address, pos = _read_str(data, 0)
        if pos >= len(data):
            return address, []
        type_tag, pos = _read_str(data, pos)
        if not type_tag.startswith(','):
            return address, []
        args: List[Any] = []
        for tag in type_tag[1:]:
            if tag == 'f':
                args.append(float(struct.unpack('>f', data[pos:pos + 4])[0]))
                pos += 4
            elif tag == 'i':
                args.append(int(struct.unpack('>i', data[pos:pos + 4])[0]))
                pos += 4
            elif tag == 's':
                s, pos = _read_str(data, pos)
                args.append(s)
            elif tag == 'T':
                args.append(True)
            elif tag == 'F':
                args.append(False)
        return address, args
    except Exception:
        return '', []

# ── Simulator ─────────────────────────────────────────────────────────────────

class XR18Simulator:
    def __init__(self, port: int = PORT, model: str = DEFAULT_MODEL):
        self._port = port
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self._sock.bind(('', port))
        self._sock.settimeout(1.0)
        self._model = model
        self._device_name = f'{model}-00-1A-79-SIM'

        self._state: Dict[str, Any] = {}
        self._state_lock = threading.Lock()

        # (ip, port) → expiry timestamp
        self._xremote: Dict[Tuple[str, int], float] = {}
        self._xremote_lock = threading.Lock()
        self._xremote_seen: set = set()  # suppress repeat log messages

        # (ip, port) → expiry timestamp for /meters/1 subscriptions
        self._meter_subs: Dict[Tuple[str, int], float] = {}
        self._meter_lock = threading.Lock()
        self._meters_enabled = True   # set to False via 'meters off' command

        self._running = False
        self._print_lock = threading.Lock()
        self._init_state()

    def _init_state(self) -> None:
        with self._state_lock:
            for ch in range(1, 17):
                cs = str(ch).zfill(2)
                self._state[f'/ch/{cs}/config/name'] = f'Ch {cs}'
                for bus in range(1, 7):
                    bs = str(bus).zfill(2)
                    self._state[f'/ch/{cs}/mix/{bs}/level'] = 0.0
                    self._state[f'/ch/{cs}/mix/{bs}/pan'] = 0.5
                    self._state[f'/ch/{cs}/mix/{bs}/grpon'] = 1  # 1 = send on (unmuted)
            for rtn in range(1, 5):
                for bus in range(1, 7):
                    bs = str(bus).zfill(2)
                    self._state[f'/rtn/{rtn}/mix/{bs}/grpon'] = 1
            for bus in range(1, 7):
                bs = str(bus).zfill(2)
                self._state[f'/rtn/aux/mix/{bs}/grpon'] = 1  # Line In
            for bus in range(1, 7):
                self._state[f'/bus/{bus}/mix/fader'] = 0.75  # ~unity (0 dB)
                self._state[f'/bus/{bus}/mix/on'] = 1         # unmuted
            self._state['/lr/mix/fader'] = 0.75  # ~unity (0 dB)
            self._state['/lr/mix/on'] = 1         # unmuted
            self._state['/config/buslink/1-2'] = 0
            self._state['/config/buslink/3-4'] = 0
            self._state['/config/buslink/5-6'] = 0

            # Snapshots — 10 pre-populated slots for testing
            _sample_names = [
                'Soundcheck', 'Band Entrada', 'Artista Solo', 'Full Band',
                'Acustico', 'Bateria Solo', 'Bajo Solo', 'Guitarra Lead',
                'Piano Solo', 'Finales',
            ]
            for i, n in enumerate(_sample_names, 1):
                self._state[f'/-snap/{str(i).zfill(2)}/name'] = n
            # Current snapshot state (0 = none loaded)
            self._state['/-snap/index'] = 0
            self._state['/-snap/name'] = ''
            self._state['/-snapstore/index'] = 0
            self._state['/-snapstore/name'] = ''

    def _local_ip(self) -> str:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(('8.8.8.8', 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return '127.0.0.1'

    def _log(self, msg: str) -> None:
        with self._print_lock:
            print(msg)

    def _send(self, addr: Tuple[str, int], data: bytes) -> None:
        try:
            self._sock.sendto(data, addr)
        except Exception as e:
            self._log(f'[SEND ERR] {addr}: {e}')

    def _push_to_xremote(self, address: str, value: Any) -> None:
        now = time.time()
        with self._xremote_lock:
            expired = [k for k, v in self._xremote.items() if v < now]
            for k in expired:
                del self._xremote[k]
                self._xremote_seen.discard(k)
            clients = list(self._xremote.keys())
        if not clients:
            return
        msg = osc_build(address, value)
        for client in clients:
            self._send(client, msg)

    def _handle(self, data: bytes, sender: Tuple[str, int]) -> None:
        address, args = osc_parse(data)
        if not address:
            return

        if address == '/xinfo':
            ip = self._local_ip()
            self._send(sender, osc_build('/xinfo', ip, self._device_name, self._model, FIRMWARE))
            self._log(f'[DISC] /xinfo from {sender[0]} → replied ({ip})')
            return

        if address == '/xremote':
            with self._xremote_lock:
                is_new = sender not in self._xremote
                self._xremote[sender] = time.time() + XREMOTE_TTL
            if is_new:
                self._xremote_seen.add(sender)
                self._log(f'[XRMT] {sender[0]}:{sender[1]} registered')
            return

        if address == '/meters' and args and args[0] == '/meters/1':
            with self._meter_lock:
                self._meter_subs[sender] = time.time() + METER_TTL
            return

        if address == '/-snap/load' and args:
            self._load_snapshot(int(args[0]), sender)
            return

        if args:
            # SET — store and push to all xremote subscribers
            value = args[0]
            with self._state_lock:
                self._state[address] = value
            self._push_to_xremote(address, value)
            self._log(f'[SET]  {address} = {value!r}')
        else:
            # GET — reply with current value
            with self._state_lock:
                value = self._state.get(address)
            if value is not None:
                self._send(sender, osc_build(address, value))
            # silently ignore unknown addresses (app may request addresses not in our model)

    def _load_snapshot(self, idx: int, requester: Tuple[str, int]) -> None:
        if not (1 <= idx <= 64):
            return
        with self._state_lock:
            name = self._state.get(f'/-snap/{str(idx).zfill(2)}/name', f'Snapshot {idx}')
            self._state['/-snap/index'] = idx
            self._state['/-snap/name'] = name
            self._state['/-snapstore/index'] = idx
            self._state['/-snapstore/name'] = name
        # Mirror what the real XR18 pushes to xremote subscribers on snapshot load.
        self._push_to_xremote('/-snap/load', 0)
        self._push_to_xremote('/-snapstore/name', name)
        self._push_to_xremote('/-snap/name', name)
        self._push_to_xremote('/-snap/index', idx)
        self._push_to_xremote('/-snapstore/index', idx)
        self._push_to_xremote('/-action/savestate', 0)
        self._push_to_xremote('/-action/mididump', 0)
        self._log(f'[SNAP] Loaded #{idx}: {name!r}  (requested by {requester[0]})')

    def _generate_meter_values(self, t: float) -> List[int]:
        """40 int16 values matching X AIR /meters/1 layout (all indices 0-based).
    [0-15]  channels 1-16 | [16-17] RTN/AUX L/R (positions 17-18 in 1-based docs)
    [18-25] FX returns 1-4 L/R | [26-31] bus outputs | [32-39] fx send/st/mon"""
        vals = [0] * 40

        # Base activity level per channel: mix of hot, medium and quiet channels
        # Values are typical signal peaks as fraction of full scale (0–1)
        activity = [0.88, 0.82, 0.55, 0.72, 0.91, 0.60, 0.78, 0.45,
                    0.86, 0.80, 0.28, 0.65, 0.70, 0.38, 0.58, 0.76]

        for i in range(16):
            base = activity[i]
            # Slow envelope: ±15 % of base so the bar breathes visibly
            envelope = base * (0.85 + 0.15 * math.sin(t * (0.35 + i * 0.04) + i * 0.7))
            # Fast signal oscillation — keeps the bar moving like real audio
            signal = envelope * (0.55 + 0.45 * abs(math.sin(t * (2.3 + i * 0.11) + i * 1.4)))
            # Occasional sharp transient that pokes into red
            peak = 0.12 * max(0.0, math.sin(t * 8.1 + i * 2.3)) ** 10
            vals[i] = _signal_to_int16(min(signal + peak, 1.0))

        # [16-17] RTN/AUX (Line In) L/R — realistic stereo signal
        for side, phase in enumerate([0.0, 0.6]):
            base = 0.72
            envelope = base * (0.80 + 0.20 * math.sin(t * 0.31 + phase))
            signal = envelope * (0.55 + 0.45 * abs(math.sin(t * 2.1 + phase)))
            peak = 0.10 * max(0.0, math.sin(t * 7.4 + phase)) ** 8
            vals[16 + side] = _signal_to_int16(min(signal + peak, 1.0))

        # [18-25] FX returns 1-4 L/R — moderate stereo signal
        fx_activity = [0.55, 0.40, 0.30, 0.20]
        for fx in range(4):
            for side, phase in enumerate([0.0, 0.5]):
                base = fx_activity[fx]
                envelope = base * (0.80 + 0.20 * math.sin(t * (0.25 + fx * 0.08) + phase))
                signal = envelope * (0.55 + 0.45 * abs(math.sin(t * (1.8 + fx * 0.12) + phase)))
                vals[18 + fx * 2 + side] = _signal_to_int16(min(signal, 1.0))

        # [26-31] bus outputs — hot mix, scaled by fader
        for i in range(6):
            with self._state_lock:
                fader = self._state.get(f'/bus/{i + 1}/mix/fader', 0.75)
            base_lvl = 0.82 * fader  # at unity (0.75) → ~0.62 baseline
            envelope = base_lvl * (0.80 + 0.20 * math.sin(t * (0.28 + i * 0.07) + i * 0.9))
            signal = envelope * (0.60 + 0.40 * abs(math.sin(t * (1.9 + i * 0.09) + i * 1.1)))
            peak = 0.10 * max(0.0, math.sin(t * 6.3 + i * 1.8)) ** 8
            vals[26 + i] = _signal_to_int16(min(signal + peak, 1.0))

        # [32-39] fx send / st / monitor — minimal
        for i in range(8):
            vals[32 + i] = _signal_to_int16(0.02 * abs(math.sin(t * 0.2 + i)))
        return vals

    def _meter_loop(self) -> None:
        t0 = time.time()
        while self._running:
            time.sleep(METER_INTERVAL)
            if not self._meters_enabled:
                continue
            now = time.time()
            with self._meter_lock:
                expired = [k for k, v in self._meter_subs.items() if v < now]
                for k in expired:
                    del self._meter_subs[k]
                clients = list(self._meter_subs.keys())
            if not clients:
                continue
            blob = build_meter_blob(self._generate_meter_values(now - t0))
            msg = osc_build('/meters/1', blob)
            for client in clients:
                self._send(client, msg)

    def _recv_loop(self) -> None:
        while self._running:
            try:
                data, sender = self._sock.recvfrom(4096)
                threading.Thread(
                    target=self._handle, args=(data, sender), daemon=True
                ).start()
            except socket.timeout:
                continue
            except Exception:
                if self._running:
                    raise
                break

    def run(self) -> None:
        self._running = True
        ip = self._local_ip()
        print(f'XR18 Simulator — {ip}:{self._port}')
        print(f'Name: {self._device_name}  |  Model: {self._model}')
        print()
        print('Commands: state [bus] | set <addr> <val> | link <1-3> <0/1> | name <ch> <name> | lr [fader x | mute x] | meters [on|off] | snap [load N | name N x] | clients | q')
        print()

        recv_thread = threading.Thread(target=self._recv_loop, daemon=True)
        recv_thread.start()
        meter_thread = threading.Thread(target=self._meter_loop, daemon=True)
        meter_thread.start()

        self._console_loop()

        self._running = False
        self._sock.close()
        print('Simulator stopped.')

    def _console_loop(self) -> None:
        while self._running:
            try:
                line = input('> ').strip()
            except (EOFError, KeyboardInterrupt):
                break

            if not line:
                continue

            parts = line.split(None, 2)
            cmd = parts[0].lower()

            if cmd in ('q', 'quit', 'exit'):
                break

            elif cmd == 'state':
                bus = int(parts[1]) if len(parts) > 1 else 1
                bs = str(bus).zfill(2)
                odd = (bus - 1) // 2 * 2 + 1
                link_addr = f'/config/buslink/{odd}-{odd + 1}'
                with self._state_lock:
                    link = self._state.get(link_addr, 0)
                    aux = self._state.get(f'/bus/{bus}/mix/fader', 0.0)
                    rows = []
                    for ch in range(1, 17):
                        cs = str(ch).zfill(2)
                        lvl = self._state.get(f'/ch/{cs}/mix/{bs}/level', 0.0)
                        pan = self._state.get(f'/ch/{cs}/mix/{bs}/pan', 0.5)
                        name = self._state.get(f'/ch/{cs}/config/name', f'Ch {cs}')
                        grpon = self._state.get(f'/ch/{cs}/mix/{bs}/grpon', 1)
                        rows.append((cs, name, lvl, pan, grpon))
                    fx_rows = []
                    for rtn in range(1, 5):
                        grpon = self._state.get(f'/rtn/{rtn}/mix/{bs}/grpon', 1)
                        fx_rows.append((rtn, grpon))
                    linein_grpon = self._state.get(f'/rtn/aux/mix/{bs}/grpon', 1)
                    aux_on = self._state.get(f'/bus/{bus}/mix/on', 1)
                print(f'\n  Bus {bus}  (buslink: {"ON" if link else "off"})')
                print(f'  {"Ch":<4} {"Name":<14} {"Level":>7}  {"Bar":<22} {"Pan":>5}  Mute')
                print(f'  {"─"*62}')
                for cs, name, lvl, pan, grpon in rows:
                    bar = '█' * int(lvl * 20)
                    pan_str = f'L{int((0.5 - pan) * 200):+.0f}' if pan < 0.49 else (
                              f'R{int((pan - 0.5) * 200):+.0f}' if pan > 0.51 else 'C')
                    mute_str = 'MUTE' if grpon == 0 else ''
                    print(f'  {cs:<4} {name:<14} {lvl:>7.3f}  [{bar:<20}] {pan_str:>5}  {mute_str}')
                print(f'  {"─"*62}')
                print(f'  AUX master: {aux:.3f} {"[MUTE]" if aux_on == 0 else ""}  |  Line In: {"MUTE" if linein_grpon == 0 else "on"}')
                fx_muted = [str(rtn) for rtn, grpon in fx_rows if grpon == 0]
                if fx_muted:
                    print(f'  FX returns muted: {", ".join(fx_muted)}')
                with self._state_lock:
                    lr_fader = self._state.get('/lr/mix/fader', 0.75)
                    lr_on = self._state.get('/lr/mix/on', 1)
                print(f'  Main LR: {lr_fader:.3f} {"[MUTE]" if lr_on == 0 else ""}')
                print()

            elif cmd == 'set':
                if len(parts) < 3:
                    print('  Usage: set <address> <value>')
                    continue
                addr = parts[1]
                raw = parts[2].strip()
                try:
                    if '.' in raw:
                        val: Any = float(raw)
                    elif raw.lstrip('-').isdigit():
                        val = int(raw)
                    else:
                        val = raw.strip('"\'')
                except ValueError:
                    val = raw
                with self._state_lock:
                    self._state[addr] = val
                self._push_to_xremote(addr, val)
                print(f'  {addr} = {val!r}  (pushed to clients)')

            elif cmd == 'link':
                # link <pair 1-3> <0|1>   →  1=1-2  2=3-4  3=5-6
                if len(parts) < 3:
                    print('  Usage: link <1|2|3> <0|1>  (1→bus1-2, 2→bus3-4, 3→bus5-6)')
                    continue
                try:
                    idx = int(parts[1])
                    val_i = int(parts[2])
                except ValueError:
                    print('  Both arguments must be integers.')
                    continue
                if idx not in (1, 2, 3) or val_i not in (0, 1):
                    print('  pair must be 1-3, value must be 0 or 1')
                    continue
                odd = (idx - 1) * 2 + 1
                addr = f'/config/buslink/{odd}-{odd + 1}'
                with self._state_lock:
                    self._state[addr] = val_i
                self._push_to_xremote(addr, val_i)
                status = 'STEREO ON' if val_i else 'mono'
                print(f'  {addr} = {val_i}  ({status}, pushed)')

            elif cmd == 'name':
                if len(parts) < 3:
                    print('  Usage: name <ch 1-16> <name>')
                    continue
                try:
                    ch = int(parts[1])
                except ValueError:
                    print('  ch must be an integer 1-16')
                    continue
                name = parts[2].strip('"\'')
                addr = f'/ch/{str(ch).zfill(2)}/config/name'
                with self._state_lock:
                    self._state[addr] = name
                self._push_to_xremote(addr, name)
                print(f'  {addr} = {name!r}  (pushed)')

            elif cmd == 'mute':
                rest_parts = line.split()
                sub = rest_parts[1].lower() if len(rest_parts) > 1 else ''
                if sub == 'aux':
                    if len(rest_parts) < 4:
                        print('  Usage: mute aux <bus 1-6> <0|1>  (0=muted, 1=unmuted)')
                        continue
                    try:
                        bus_n = int(rest_parts[2])
                        val_i = int(rest_parts[3])
                    except ValueError:
                        print('  Both arguments must be integers.')
                        continue
                    if val_i not in (0, 1):
                        print('  Value must be 0 (muted) or 1 (unmuted)')
                        continue
                    if not 1 <= bus_n <= 6:
                        print('  bus must be 1-6')
                        continue
                    addr = f'/bus/{bus_n}/mix/on'
                    with self._state_lock:
                        self._state[addr] = val_i
                    self._push_to_xremote(addr, val_i)
                    status = 'MUTED' if val_i == 0 else 'unmuted'
                    print(f'  {addr} = {val_i}  ({status}, pushed)')
                    continue
                else:
                    print('  Usage: mute aux <bus 1-6> <0|1>  (0=muted, 1=unmuted)')

            elif cmd == 'lr':
                sub = parts[1].lower() if len(parts) > 1 else ''
                if sub == 'fader':
                    if len(parts) < 3:
                        print('  Usage: lr fader <0.0-1.0>')
                        continue
                    try:
                        val_f = float(parts[2])
                    except ValueError:
                        print('  Value must be a float 0.0-1.0')
                        continue
                    val_f = max(0.0, min(1.0, val_f))
                    with self._state_lock:
                        self._state['/lr/mix/fader'] = val_f
                    self._push_to_xremote('/lr/mix/fader', val_f)
                    print(f'  /lr/mix/fader = {val_f:.3f}  (pushed)')
                elif sub == 'mute':
                    if len(parts) < 3:
                        print('  Usage: lr mute <0|1>  (0=muted, 1=unmuted)')
                        continue
                    try:
                        val_i = int(parts[2])
                    except ValueError:
                        print('  Value must be 0 (muted) or 1 (unmuted)')
                        continue
                    if val_i not in (0, 1):
                        print('  Value must be 0 (muted) or 1 (unmuted)')
                        continue
                    with self._state_lock:
                        self._state['/lr/mix/on'] = val_i
                    self._push_to_xremote('/lr/mix/on', val_i)
                    status = 'MUTED' if val_i == 0 else 'unmuted'
                    print(f'  /lr/mix/on = {val_i}  ({status}, pushed)')
                else:
                    with self._state_lock:
                        lr_fader = self._state.get('/lr/mix/fader', 0.75)
                        lr_on = self._state.get('/lr/mix/on', 1)
                    mute_str = '  [MUTE]' if lr_on == 0 else ''
                    print(f'  Main LR: fader={lr_fader:.3f}{mute_str}')

            elif cmd == 'meters':
                arg = parts[1].lower() if len(parts) > 1 else ''
                if arg == 'off':
                    self._meters_enabled = False
                    print('  Meter simulation OFF — app will show "sin conexión" after ~15s')
                elif arg == 'on':
                    self._meters_enabled = True
                    print('  Meter simulation ON')
                else:
                    now = time.time()
                    with self._meter_lock:
                        subs = [(k, v - now) for k, v in self._meter_subs.items()]
                    state = 'ON' if self._meters_enabled else 'OFF'
                    print(f'  Meter simulation: {state}')
                    if subs:
                        for (cip, cport), ttl in subs:
                            print(f'    subscriber {cip}:{cport}  ttl={ttl:.1f}s')
                    else:
                        print('  No meter subscribers yet.')

            elif cmd == 'snap':
                sub = parts[1].lower() if len(parts) > 1 else ''
                if sub == 'load':
                    if len(parts) < 3:
                        print('  Usage: snap load <1-64>')
                        continue
                    try:
                        idx = int(parts[2])
                    except ValueError:
                        print('  N must be an integer')
                        continue
                    if not (1 <= idx <= 64):
                        print('  N must be between 1 and 64')
                        continue
                    self._load_snapshot(idx, ('console', 0))
                elif sub == 'name':
                    rest = line.split(None, 3)
                    if len(rest) < 4:
                        print('  Usage: snap name <N> <name>')
                        continue
                    try:
                        idx = int(rest[2])
                    except ValueError:
                        print('  N must be an integer')
                        continue
                    name = rest[3].strip('"\'')
                    addr = f'/-snap/{str(idx).zfill(2)}/name'
                    with self._state_lock:
                        self._state[addr] = name
                    print(f'  {addr} = {name!r}')
                else:
                    # List all snapshots
                    with self._state_lock:
                        current = self._state.get('/-snap/index', 0)
                        rows = []
                        for i in range(1, 65):
                            n = self._state.get(f'/-snap/{str(i).zfill(2)}/name')
                            if n:
                                rows.append((i, n))
                    print(f'\n  {"#":<5} {"Name":<30}')
                    print(f'  {"─"*36}')
                    for i, n in rows:
                        marker = ' ◀' if i == current else ''
                        print(f'  {i:<5} {n:<30}{marker}')
                    if not rows:
                        print('  (no snapshots defined)')
                    print()

            elif cmd == 'clients':
                now = time.time()
                with self._xremote_lock:
                    clients = sorted(
                        ((k, v - now) for k, v in self._xremote.items()),
                        key=lambda x: x[0]
                    )
                if clients:
                    print('  xremote clients:')
                    for (cip, cport), ttl in clients:
                        status = f'OK, expires in {ttl:.1f}s' if ttl > 0 else 'EXPIRED'
                        print(f'    {cip}:{cport}  — {status}')
                else:
                    print('  No clients registered.')

            elif cmd == 'help':
                print('  state [bus]                  Show fader/mute state for a bus (default 1)')
                print('  set <addr> <val>             Set any OSC address and push to app')
                print('  link <1|2|3> <0|1>          Toggle stereo pairing for bus pair')
                print('  name <ch> <name>             Set channel name (ch = 1-16)')
                print('  mute aux <bus> <0|1>         Set AUX bus on/off (0=muted, 1=unmuted)')
                print('  lr                           Show Main LR fader and mute state')
                print('  lr fader <0.0-1.0>           Set Main LR fader level and push')
                print('  lr mute <0|1>                Set Main LR mute (0=muted, 1=unmuted) and push')
                print('  meters [on|off]              Show or toggle VU meter simulation')
                print('    off → stops /meters/1; app shows "sin conexión" after ~15s')
                print('  snap                         List all snapshots')
                print('  snap load <N>                Load snapshot N (pushes /-snap/index to app)')
                print('  snap name <N> <name>         Set snapshot name')
                print('  clients                      Show registered /xremote clients')
                print('  q / quit                     Exit')

            else:
                print(f'  Unknown command: {cmd}. Type "help" for help.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Behringer XR18 OSC Simulator')
    parser.add_argument('--port', type=int, default=PORT,
                        help=f'UDP port to listen on (default: {PORT})')
    parser.add_argument('--model', type=str, default=DEFAULT_MODEL,
                        help=f'Model name reported in /xinfo (default: {DEFAULT_MODEL})')
    args = parser.parse_args()
    XR18Simulator(port=args.port, model=args.model).run()
