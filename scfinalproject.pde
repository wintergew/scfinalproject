import java.net.Socket;
import java.io.DataInputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import oscP5.*;
import netP5.*;

// ─── Network & Config
static final String BRIDGE_HOST = "127.0.0.1";
static final int    BRIDGE_PORT = 7400;

static final boolean WEKINATOR_ENABLED = true;
static final String  WEK_HOST          = "127.0.0.1";
static final int     WEK_SEND_PORT     = 6448;   
static final int     WEK_RECV_PORT     = 12001;  

boolean DEBUG_MODE = false;

// ─── Protocol Constants
static final int GESTURE_MAX_LEN = 32;
static final int NUM_HAND_JOINTS = 21;
static final int NUM_FACE_POINTS = 478;
static final int NUM_BLENDSHAPES = 52;

// ─── Color palette
final color COL_BG         = #fefae0;
final color COL_TEXT       = #283618;
final color COL_PANEL_BG   = color(221, 161, 94, 220); // #dda15e with transparency
final color COL_HAND_RIGHT = #bc6c25;
final color COL_HAND_LEFT  = #606c38;
final color COL_FACE       = color(96, 108, 56, 150);  // #606c38 with transparency
final color COL_HIGHLIGHT  = #dda15e;

// ─── Statuses
Socket          bridgeSocket;
DataInputStream bridgeDIS;
Thread          bridgeThread;
boolean         bridgeConnected = false;

OscP5      oscP5_wek;
NetAddress wekAddr;

PVector[][] handLandmarks  = new PVector[2][NUM_HAND_JOINTS];
String[]    handedness     = {"", ""};
float[]     handConfidence = {0f, 0f};
String[]    gestureName    = {"None", "None"};
float[]     gestureScore   = {0f, 0f};
int         numHandsActive = 0;

PVector[] faceLandmarks = new PVector[NUM_FACE_POINTS];
boolean   hasFaceActive = false;

boolean showHands   = true;
boolean showFace    = false;
boolean showGesture = false;
boolean isFullscreen = false;

// ─── AAC TTS Phrases
int lastSpokenIdx = -1;
int lastSpokenTime = 0;
Process currentTTSProcess = null;
PImage[] assetImages = new PImage[12];

String[] aacPhrases = {
  "I", "you", "yes", "no", "want", "feel",
  "good", "bad", "dessert", "food", "water", "toilet"
};

// ─── Topologies
static final int[][] HAND_CONNECTIONS = {
  {0, 1}, {1, 2}, {2, 3}, {3, 4}, {0, 5}, {5, 6}, {6, 7}, {7, 8}, {0, 9}, {9, 10}, {10, 11}, {11, 12},
  {0, 13}, {13, 14}, {14, 15}, {15, 16}, {0, 17}, {17, 18}, {18, 19}, {19, 20}, {5, 9}, {9, 13}, {13, 17}
};

static final int[][] FACE_CONTOURS = {
  // Eyes
  {33, 7}, {7, 163}, {163, 144}, {144, 145}, {145, 153}, {153, 154}, {154, 155}, {155, 133}, {133, 246}, {246, 161}, {161, 160}, {160, 159}, {159, 158}, {158, 157}, {157, 173}, {173, 33},
  {362, 382}, {382, 381}, {381, 380}, {380, 374}, {374, 373}, {373, 390}, {390, 249}, {249, 263}, {263, 466}, {466, 388}, {388, 387}, {387, 386}, {386, 385}, {385, 384}, {384, 398}, {398, 362},
  // Brows
  {70, 63}, {63, 105}, {105, 66}, {66, 107}, {107, 55}, {55, 193}, {193, 168},
  {300, 293}, {293, 334}, {334, 296}, {296, 336}, {336, 285}, {285, 417}, {417, 168},
  // Nose & Lips
  {168, 6}, {6, 197}, {197, 195}, {195, 5}, {5, 4}, {4, 1}, {1, 19}, {19, 94}, {94, 2},
  {61, 185}, {185, 40}, {40, 39}, {39, 37}, {37, 0}, {0, 267}, {267, 269}, {269, 270}, {270, 409}, {409, 291}, {291, 375}, {375, 321}, {321, 405}, {405, 314}, {314, 17}, {17, 84}, {84, 181}, {181, 91}, {91, 146}, {146, 61},
  {78, 191}, {191, 80}, {80, 81}, {81, 82}, {82, 13}, {13, 312}, {312, 311}, {311, 310}, {310, 415}, {415, 308}, {308, 324}, {324, 318}, {318, 402}, {402, 317}, {317, 14}, {14, 87}, {87, 178}, {178, 88}, {88, 95}, {95, 78},
  // Oval
  {10, 338}, {338, 297}, {297, 332}, {332, 284}, {284, 251}, {251, 389}, {389, 356}, {356, 454}, {454, 323}, {323, 361}, {361, 288}, {288, 397}, {397, 365}, {365, 379}, {379, 378}, {378, 400}, {400, 377}, {377, 152}, {152, 148}, {148, 176}, {176, 149}, {149, 150}, {150, 136}, {136, 172}, {172, 58}, {58, 132}, {132, 93}, {93, 234}, {234, 127}, {127, 162}, {162, 21}, {21, 54}, {54, 103}, {103, 67}, {67, 109}, {109, 10}
};

// ─── setup
void setup() {
  size(1280, 720);
  surface.setResizable(true);
  smooth(8);

  for (int i = 0; i < 12; i++) {
    assetImages[i] = loadImage("assets/" + (i + 1) + ".jpg");
  }

  for (int h = 0; h < 2; h++)
    for (int j = 0; j < NUM_HAND_JOINTS; j++)
      handLandmarks[h][j] = new PVector();

  for (int i = 0; i < NUM_FACE_POINTS; i++)
    faceLandmarks[i] = new PVector();

  if (WEKINATOR_ENABLED) {
    oscP5_wek = new OscP5(this, WEK_RECV_PORT);
    wekAddr   = new NetAddress(WEK_HOST, WEK_SEND_PORT);
    println("[Wekinator] Sending 84 hand floats to port " + WEK_SEND_PORT);
  }

  startBridgeThread();
}

// ─── Draw Loop
float[] boxMinX = {0, 0};
float[] boxMaxX = {1, 1};
float[] boxMinY = {0, 0};
float[] boxMaxY = {1, 1};

void draw() {
  background(COL_BG);

  for (int h = 0; h < 2; h++) {
    if (h < numHandsActive) {
      boxMinX[h] = 1.0f;
      boxMaxX[h] = 0.0f;
      boxMinY[h] = 1.0f;
      boxMaxY[h] = 0.0f;
      for (int j = 0; j < NUM_HAND_JOINTS; j++) {
        float x = handLandmarks[h][j].x;
        float y = handLandmarks[h][j].y;
        if (x < boxMinX[h]) boxMinX[h] = x;
        if (x > boxMaxX[h]) boxMaxX[h] = x;
        if (y < boxMinY[h]) boxMinY[h] = y;
        if (y > boxMaxY[h]) boxMaxY[h] = y;
      }
      // Padding
      float pad = 0.01f;
      boxMinX[h] -= pad;
      boxMaxX[h] += pad;
      boxMinY[h] -= pad;
      boxMaxY[h] += pad;
    } else {
      boxMinX[h] = 0;
      boxMaxX[h] = 1;
      boxMinY[h] = 0;
      boxMaxY[h] = 1;
    }
  }

  if (showFace)    drawFaceMesh();
  if (showHands) {
    for (int h = 0; h < numHandsActive; h++) {
      stroke(COL_HIGHLIGHT);
      strokeWeight(2);
      noFill();
      rect(boxMinX[h] * width, boxMinY[h] * height, (boxMaxX[h] - boxMinX[h]) * width, (boxMaxY[h] - boxMinY[h]) * height, 8);
    }

    drawHandSkeleton(0);
    drawHandSkeleton(1);
  }
  if (showGesture) drawGestureHUD();

  drawStatusPanel();

  // Send hand landmarks
  sendToWekinator();
}

// ─── Drawing
void drawHandSkeleton(int h) {
  if (h >= numHandsActive) return;

  boolean isRight = handedness[h].equals("Right");
  color boneCol   = isRight ? COL_HAND_RIGHT : COL_HAND_LEFT;

  strokeWeight(2.5f);
  stroke(boneCol);
  noFill();

  for (int[] c : HAND_CONNECTIONS) {
    PVector a = screenPt(handLandmarks[h][c[0]]);
    PVector b = screenPt(handLandmarks[h][c[1]]);
    line(a.x, a.y, b.x, b.y);
  }

  noStroke();
  fill(boneCol);
  for (int j = 0; j < NUM_HAND_JOINTS; j++) {
    PVector p = screenPt(handLandmarks[h][j]);
    float r = (j == 0) ? 9f : 5f;
    ellipse(p.x, p.y, r, r);
  }

  PVector wrist = screenPt(handLandmarks[h][0]);
  fill(COL_TEXT);
  textAlign(CENTER, BOTTOM);
  textSize(14);
  text(handedness[h] + " (" + nf(handConfidence[h]*100, 0, 0) + "%)", wrist.x, wrist.y - 12);
}

void drawFaceMesh() {
  if (!hasFaceActive) return;

  stroke(COL_FACE);
  strokeWeight(1.0f);
  noFill();

  for (int[] e : FACE_CONTOURS) {
    if (e[0] < NUM_FACE_POINTS && e[1] < NUM_FACE_POINTS) {
      PVector a = screenPt(faceLandmarks[e[0]]);
      PVector b = screenPt(faceLandmarks[e[1]]);
      line(a.x, a.y, b.x, b.y);
    }
  }
}

void drawGestureHUD() {
  if (numHandsActive == 0) return;

  int hudW = 220, hudH = numHandsActive * 60 + 10, hudX = width - hudW - 16, hudY = 16;

  noStroke();
  fill(COL_PANEL_BG);
  rect(hudX, hudY, hudW, hudH, 8);

  int py = hudY + 12;
  for (int h = 0; h < numHandsActive; h++) {
    fill(COL_TEXT);
    textAlign(LEFT, TOP);
    textSize(12);
    text(handedness[h], hudX + 12, py);

    textSize(18);
    text(gestureName[h].replace("_", " "), hudX + 12, py + 16);

    textAlign(RIGHT, TOP);
    textSize(14);
    text(nf(gestureScore[h]*100, 0, 0) + "%", hudX + hudW - 12, py + 20);

    py += 60;
  }
}

void drawStatusPanel() {
  int pw = 250, ph = 120, px = 12, py = 12;

  noStroke();
  fill(COL_PANEL_BG);
  rect(px, py, pw, ph, 8);

  fill(COL_TEXT);
  textAlign(LEFT, TOP);
  textSize(12);

  int tx = px + 12, ty = py + 12, lh = 18;

  text("Bridge: " + (bridgeConnected ? "CONNECTED" : "waiting…"), tx, ty);
  ty += lh;
  text("Hands: " + numHandsActive, tx, ty);
  ty += lh;
  text("Face: " + (hasFaceActive ? "YES" : "NO"), tx, ty);
  ty += lh;
  text("Wekinator: " + (WEKINATOR_ENABLED ? "SENDING (port "+WEK_SEND_PORT+")" : "OFF"), tx, ty);
  ty += lh;

  ty += 6;
  textSize(10);
  text("[H] hands  [G] gestures  [F] face  [D] debug: " + (DEBUG_MODE ? "ON" : "OFF"), tx, ty);

  // Draw the gesture asset image
  if (lastSpokenIdx >= 0 && lastSpokenIdx < 12) {
    if (millis() - lastSpokenTime < 4000) {
      PImage img = assetImages[lastSpokenIdx];
      if (img != null && img.width > 0) {
        float maxImgW = pw - 20; 
        float maxImgH = 250;
        float aspect = (float)img.width / img.height;
        float drawW = maxImgW;
        float drawH = drawW / aspect;
        if (drawH > maxImgH) {
          drawH = maxImgH;
          drawW = drawH * aspect;
        }

        float imgY = py + ph + 12;
        fill(COL_PANEL_BG);
        rect(px, imgY, drawW + 20, drawH + 20, 8);
        image(img, px + 10, imgY + 10, drawW, drawH);
      }
    }
  }
}

PVector screenPt(PVector lm) {
  return new PVector(lm.x * width, lm.y * height);
}

// ─── Network
void sendToWekinator() {
  if (!WEKINATOR_ENABLED || wekAddr == null) return;
  if (numHandsActive == 0) return; 

  OscMessage msg = new OscMessage("/wek/inputs");

  // Sends exactly 84 floats (2 hands × 21 joints × x,y coords)
  // Normalized relative to the dynamic bounding box of each active hand
  for (int h = 0; h < 2; h++) {
    float bw = boxMaxX[h] - boxMinX[h];
    float bh = boxMaxY[h] - boxMinY[h];
    if (bw < 0.001f) bw = 0.001f; // Prevent division by zero
    if (bh < 0.001f) bh = 0.001f;

    for (int j = 0; j < NUM_HAND_JOINTS; j++) {
      float nx = (handLandmarks[h][j].x - boxMinX[h]) / bw;
      float ny = (handLandmarks[h][j].y - boxMinY[h]) / bh;
      msg.add(nx);
      msg.add(ny);
    }
  }

  oscP5_wek.send(msg, wekAddr);
}

void oscEvent(OscMessage msg) {
  if (DEBUG_MODE) {
    println("\n====================================");
    println("WEKINATOR TRIGGERED:");
    msg.print();
    println("====================================\n");
  }

  String addr = msg.addrPattern();

  if (addr.startsWith("/11_")) {
    try {
      int idx = Integer.parseInt(addr.substring(4)) - 1;
      speakPhrase(idx);
    }
    catch (Exception e) {
      if (DEBUG_MODE) println("[TTS] DTW parse error: " + e.getMessage());
    }
  }
  // Classification format: e.g. /wek/outputs with float arg (1.0, 2.0...)
  else if (addr.equals("/wek/outputs")) {
    if (msg.checkTypetag("f")) {
      int classNum = (int) msg.get(0).floatValue();
      speakPhrase(classNum - 1);
    } else {
      if (DEBUG_MODE) println("[TTS] Classifier output missing float argument");
    }
  }
}

void speakPhrase(int idx) {
  if (idx < 0 || idx >= aacPhrases.length) return;

  int now = millis();

  if (idx == lastSpokenIdx && (now - lastSpokenTime) < 4000) {
    return;
  }

  if (currentTTSProcess != null && currentTTSProcess.isAlive()) {
    currentTTSProcess.destroy();
  }

  String phrase = aacPhrases[idx];
  if (DEBUG_MODE) println("[AAC SPEAK] Saying: " + phrase);

  try {
    currentTTSProcess = Runtime.getRuntime().exec(new String[]{"say", phrase});
    lastSpokenIdx = idx;
    lastSpokenTime = now;
  }
  catch (Exception e) {
    if (DEBUG_MODE) println("[TTS] Error triggering phrase: " + e.getMessage());
  }
}

void startBridgeThread() {
  bridgeThread = new Thread(() -> {
    while (true) {
      if (!bridgeConnected) {
        try {
          bridgeSocket = new Socket(BRIDGE_HOST, BRIDGE_PORT);
          bridgeSocket.setTcpNoDelay(true);
          bridgeDIS = new DataInputStream(bridgeSocket.getInputStream());
          bridgeConnected = true;
          println("[Bridge] Connected to mediapipe_bridge.py");
        }
        catch (Exception e) {
          try {
            Thread.sleep(1000);
          }
          catch (Exception ignored) {
          }
          continue;
        }
      }

      try {
        int payloadLen = bridgeDIS.readInt();
        byte[] frame = new byte[payloadLen];
        bridgeDIS.readFully(frame);
        parseFrame(frame);
      }
      catch (Exception e) {
        bridgeConnected = false;
        try {
          bridgeSocket.close();
        }
        catch (Exception ignored) {
        }
      }
    }
  }
  );
  bridgeThread.setDaemon(true);
  bridgeThread.start();
}

void parseFrame(byte[] frame) {
  ByteBuffer buf = ByteBuffer.wrap(frame);
  buf.order(ByteOrder.BIG_ENDIAN);

  int numHands = buf.get() & 0xFF;
  int hasFace  = buf.get() & 0xFF;
  buf.get(); // hasBs
  buf.get(); // reserved

  byte[] gNameBytes = new byte[GESTURE_MAX_LEN];
  for (int h = 0; h < 2; h++) {
    int side = buf.get() & 0xFF;
    float hConf = buf.getFloat();
    buf.get(gNameBytes);
    float gConf = buf.getFloat();

    int nameEnd = 0;
    while (nameEnd < GESTURE_MAX_LEN && gNameBytes[nameEnd] != 0) nameEnd++;
    String gName = new String(gNameBytes, 0, nameEnd, StandardCharsets.US_ASCII);

    for (int j = 0; j < NUM_HAND_JOINTS; j++) {
      float x = buf.getFloat();
      float y = buf.getFloat();
      float z = buf.getFloat();
      if (h < numHands) {
        handLandmarks[h][j].set(x, y, z);
      }
    }

    if (h < numHands) {
      handedness[h]     = (side == 0) ? "Right" : (side == 1) ? "Left" : "";
      handConfidence[h] = hConf;
      gestureName[h]    = gName.isEmpty() ? "None" : gName;
      gestureScore[h]   = gConf;
    }
  }

  numHandsActive = numHands;

  for (int i = 0; i < NUM_FACE_POINTS; i++) {
    float x = buf.getFloat();
    float y = buf.getFloat();
    float z = buf.getFloat();
    if (hasFace == 1) {
      faceLandmarks[i].set(x, y, z);
    }
  }

  // Skip blendshapes
  for (int i = 0; i < NUM_BLENDSHAPES; i++) {
    buf.getFloat();
  }

  hasFaceActive = (hasFace == 1);
}

void keyPressed() {
  switch (Character.toUpperCase(key)) {
  case 'H':
    showHands   = !showHands;
    break;
  case 'G':
    showGesture = !showGesture;
    break;
  case 'F':
    showFace    = !showFace;
    break;
  case 'D':
    DEBUG_MODE  = !DEBUG_MODE;
    break;
  case 'T':
    testTTS();
    break;
  case ' ':
    isFullscreen = !isFullscreen;
    if (isFullscreen) {
      surface.setSize(displayWidth, displayHeight);
      surface.setLocation(0, 0);
    } else {
      surface.setSize(1280, 720);
      surface.setLocation(80, 80);
    }
    break;
  }
}

void testTTS() {
  int idx = (int) random(aacPhrases.length);
  String phrase = aacPhrases[idx];
  println("[TTS] " + phrase);
  try {
    Runtime.getRuntime().exec(new String[]{"say", phrase});
  }
  catch (IOException e) {
    println("[TTS] Error: " + e.getMessage());
  }
}

