# LoopLine

A real-time currency arbitrage detector built with Flutter and a Dart backend. It models forex exchange rates as a weighted directed graph and uses **Bellman-Ford negative cycle detection** to spot arbitrage opportunities as live rates stream in.

---

## How It Works

Arbitrage exists when a chain of currency conversions ends with more money than you started with, e.g. `USD → EUR → GBP → USD` returning more than 1 USD per 1 USD.

1. **Graph model**: each currency is a vertex, and each exchange rate is a directed edge.
2. **Log transform**: a rate `r` becomes an edge weight of `-log(r)`. A product of rates greater than 1 becomes a sum of weights less than 0.
3. **Cycle detection**: Bellman-Ford finds negative-weight cycles, and each one is an arbitrage loop.
4. **Profit calculation**: the cycle is converted back into a percentage gain.

```
rate(A→B) × rate(B→C) × rate(C→A) > 1
        ⇔  -log(rA→B) + -log(rB→C) + -log(rC→A) < 0
```

## Features

- Live forex rates streamed over the Finnhub WebSocket (OANDA symbols, e.g. `OANDA:EUR_USD`)
- Bellman-Ford negative cycle detection with debounced recompute
- Per-pair staleness checks so outdated rates don't produce false opportunities
- Flutter frontend showing detected arbitrage cycles and estimated profit
- Dart `shelf` backend that fetches rates and runs the detection

## Tech Stack

| Layer | Technology |
|-------|------------|
| Frontend | Flutter / Dart |
| Backend | Dart (`shelf`) |
| Live data | Finnhub forex WebSocket |
| Algorithm | Bellman-Ford on a weighted digraph |

## Project Structure

```
loopline/
├──lib/
  ├── backend/     # Dart shelf server: rate feed + arbitrage detection
  └── frontend/    # Flutter client
  └── main.dart    # Execution start
```

##  Screen Images
<img height="400" alt="Screenshot 2026-10-24 at 3 06 11 PM" src="https://github.com/user-attachments/assets/0f38aa2b-53b2-4d1e-a1c4-5edf638eb880" /> <img height="400" alt="Screenshot 2026-10-24 at 3 04 08 PM" src="https://github.com/user-attachments/assets/fa38d596-32a4-496b-9104-1a52b6d8b1d8" /> <br>
<img height="400" alt="Screenshot 2026-10-24 at 3 04 47 PM" src="https://github.com/user-attachments/assets/686779df-6e2a-403b-a0c2-4e516c875f92" />
<img height="400" alt="Screenshot 2026-10-24 at 3 05 06 PM" src="https://github.com/user-attachments/assets/4f119411-ac44-472e-b727-0613eaac2b9f" />




### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- Dart SDK (bundled with Flutter)
- A free [Finnhub](https://finnhub.io) API key


- [ ] Transaction fee and spread modelling

## Disclaimer

Detected opportunities are theoretical: real-world execution is affected by spreads, fees, latency, and slippage. Not financial advice.
There exists sample data which is highly modified and is there for testing purposes for now
