# Sound Communication Hand Signal Interpreter Final Project

This is the project we've created with [Ilayda Takir](https://github.com/ilaydatakir) in UPF CSIM program Sound Communication course. This project interpret the hand signals and convert them into OSC messages to be used in any osc-compatible software. We've used wekinator to create a machine learning model that can recognize hand gestures and convert them into OSC messages.

The sketch connects to `127.0.0.1:7400` in a background thread. The status panel shows **CONNECTED** once the handshake succeeds.

You will also need [mppbridge](https://github.com/wintergew/mppbridge) to be able to receive the information from mediapipe

## Video Demo

<https://raw.githubusercontent.com/wintergew/scfinalproject/refs/heads/master/repo_assets/demo.mp4>

## Keyboard controls (in Processing)

| Key | Action |
|-----|--------|
| `D` | Toggle status panel |
| `H` | Toggle hand skeleton |
| `G` | Toggle gesture HUD |
| `F` | Toggle face mesh |
| `SPACE` | Toggle fullscreen |

## Wekinator Integration

Wekinator OSC is sent **from Processing** (not from mppbridge).

The sketch sends exactly **84 inputs** to Wekinator continuously.
This corresponds to the X and Y coordinates of 21 joints for 2 hands (`2 × 21 × 2 = 84`).

## How to configure Wekinator

1. Open Wekinator and start a new project.
2. **Inputs**: Set `# inputs` to **84**.
3. **OSC In**: Set the port to **6448** (Processing sends to this port).
4. **Outputs**: Use 12 classifier outputs to classify the hand gestures.
5. **OSC Out**: Set the port to **12001** (Processing listens for outputs here if you choose to map them back).
6. **Training data**: Train the model in wekinator by doing the hand gestures and recording the data. The gestures we've added are as follows:

```
1. I / me / my
2. you / your
3. yes
4. no
5. want
6. feel
7. good
8. bad
9. dessert
10. food
11. water
12. toilet
```
