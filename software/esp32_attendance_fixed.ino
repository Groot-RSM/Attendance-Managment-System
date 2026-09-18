#include <Arduino.h>
#include <Adafruit_Fingerprint.h>
#include <SPI.h>
#include <SD.h>
#include <WiFi.h>
#include <WebServer.h>
#include "time.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h>
// #include <Keypad.h>

#define i2c_Address 0x3C // The scanner confirmed it is 0x3C
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SH1106G display = Adafruit_SH1106G(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

/* 
const byte ROWS = 4;
const byte COLS = 4;
char keys[ROWS][COLS] = {
  {'1','2','3','A'},
  {'4','5','6','B'},
  {'7','8','9','C'},
  {'*','0','#','D'}
};
byte rowPins[ROWS] = {13, 12, 14, 27};
byte colPins[COLS] = {26, 25, 33, 32};
Keypad customKeypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);
*/

// WiFi Credentials
const char* ssid = "Madhu HariesH's A15";
const char* password = "leftright12";

// NTP Server settings
const char* ntpServer = "pool.ntp.org";
const long  gmtOffset_sec = 19800; // GMT +5:30
const int   daylightOffset_sec = 0;

#define SD_CS_PIN 5

// Web Server
WebServer server(80);

// BLE Configuration - Nordic UART Service (NUS)
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic;
bool deviceConnected = false;
bool oldDeviceConnected = false;

String bleCommand = "";
bool bleCommandPending = false;
bool bleReceiving = false;
uint32_t bleDataTime = 0;

// BLE File Upload Variables
bool isReceivingFile = false;
File uploadFile;
String uploadFileName = "";

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("BLE Connected!");
    };
    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("BLE Disconnected!");
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      uint8_t* rxData = pCharacteristic->getData();
      size_t rxLength = pCharacteristic->getLength();

      if (rxLength > 0) {
        if (isReceivingFile) {
          // Check if this chunk contains CMD:EOF (we do a simple string check)
          String chunk = "";
          for (size_t i = 0; i < rxLength; i++) {
            chunk += (char)rxData[i];
          }
          if (chunk.indexOf("CMD:EOF") >= 0) {
            // EOF received, stop receiving
            if (uploadFile) {
              uploadFile.close();
              Serial.println("✅ File upload complete: " + uploadFileName);
            }
            isReceivingFile = false;
            
            // Send confirmation
            String ack = "UPLOAD_DONE\n";
            pTxCharacteristic->setValue((uint8_t*)ack.c_str(), ack.length());
            pTxCharacteristic->notify();
          } else {
            // Write data to file
            if (uploadFile) {
              uploadFile.write(rxData, rxLength);
            }
          }
          return; // Skip normal command processing
        }

        bleDataTime = millis(); // Reset timeout FIRST to prevent loop() race condition!
        if (!bleReceiving) {
          bleCommand = "";
          bleReceiving = true;
        }
        
        Serial.print("BLE Chunk Rx Length: ");
        Serial.println(rxLength);
        
        for (size_t i = 0; i < rxLength; i++) {
          bleCommand += (char)rxData[i];
        }
        bleDataTime = millis(); // Refresh timeout after appending
      }
    }
};

// ESP32 Hardware Serial 2 configuration
HardwareSerial serialPort(2);
Adafruit_Fingerprint finger = Adafruit_Fingerprint(&serialPort);

String currentInput = ""; // Buffer for input

// System States
enum SystemState {
  STATE_MENU,
  STATE_ENROLL_WAIT_ID,
  STATE_ATTENDANCE_MODE,
  STATE_DOWNLOAD_TEMPLATE
};

SystemState currentState = STATE_MENU;
uint16_t pendingEnrollID = 0;

// Function Prototypes
void printMenu();
uint8_t getFingerprintEnroll(uint16_t id);
void checkAttendance();
void clearSerialBuffer();
void saveTemplateToSD(uint16_t id);
void logAttendance(uint16_t id);
void logScannedTemplate(uint16_t id, struct tm* timeinfo);
bool isStudentRegistered(uint16_t id);

void showScreen(String title, String l1, String l2 = "", String l3 = "") {
  display.clearDisplay();
  
  // Title Bar (Inverted)
  display.fillRect(0, 0, 128, 16, SH110X_WHITE);
  display.setTextColor(SH110X_BLACK, SH110X_WHITE);
  display.setTextSize(1);
  display.setCursor(2, 4);
  display.println(title);

  // Content
  display.setTextColor(SH110X_WHITE, SH110X_BLACK);
  display.setTextSize(1);
  
  display.setCursor(0, 20);
  display.println(l1);
  
  display.setCursor(0, 32);
  display.println(l2);
  
  display.setCursor(0, 44);
  display.println(l3);
  
  display.display();
  
  // Also print to Serial for debugging
  Serial.println("\n[" + title + "]");
  Serial.println(l1);
  if(l2 != "") Serial.println(l2);
  if(l3 != "") Serial.println(l3);
}

void setup() {
  Serial.begin(115200);
  while (!Serial);
  delay(100);
  
  Wire.begin(21, 22); // SDA, SCL
  if (!display.begin(i2c_Address, true)) {
    Serial.println("❌ OLED allocation failed");
  }
  display.display(); // show splash
  delay(1000);
  display.clearDisplay();
  
  showScreen("BOOTING", "ESP32 Attendance", "V1.0", "Starting...");

  // Initialize SD Card
  showScreen("BOOTING", "Initializing SD...");
  if (!SD.begin(SD_CS_PIN)) {
    showScreen("ERROR", "SD Card Failed!", "Check wiring");
    delay(2000);
  } else {
    showScreen("BOOTING", "SD Card OK!");
  }

  // Connect to Wi-Fi
  showScreen("BOOTING", "Connecting Wi-Fi", ssid);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  showScreen("BOOTING", "Wi-Fi Connected!", WiFi.localIP().toString());
  delay(1000);
  
  // Setup Web Server
  server.on("/", HTTP_GET, []() {
    String html = "<html><head><title>ESP32 Attendance</title>";
    html += "<meta name='viewport' content='width=device-width, initial-scale=1.0'>";
    html += "<style>body{font-family:Arial; padding:20px;} a{display:block; padding:10px; margin:5px 0; background:#007bff; color:white; text-decoration:none; border-radius:5px; text-align:center;}</style>";
    html += "</head><body><h2>Attendance Logs</h2>";
    
    File root = SD.open("/");
    root.rewindDirectory();
    File file = root.openNextFile();
    bool hasFiles = false;
    while (file) {
      if (!file.isDirectory()) {
        String fname = String(file.name());
        if (fname.endsWith(".csv")) {
          html += "<a href='/" + fname + "'>" + fname + "</a>";
          hasFiles = true;
        }
      }
      file = root.openNextFile();
    }
    if (!hasFiles) html += "<p>No CSV files found on SD card.</p>";
    html += "</body></html>";
    server.send(200, "text/html", html);
  });

  server.onNotFound([]() {
    String path = server.uri();
    if (SD.exists(path)) {
      File file = SD.open(path);
      server.streamFile(file, "text/csv");
      file.close();
    } else {
      server.send(404, "text/plain", "File Not Found");
    }
  });

  server.begin();
  showScreen("BOOTING", "Web Server started!");

  // Initialize NTP Time
  configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
  showScreen("BOOTING", "Time synced!");

  // Initialize fingerprint sensor on Pins 16 (RX) and 17 (TX)
  serialPort.begin(57600, SERIAL_8N1, 16, 17);
  
  if (finger.verifyPassword()) {
    showScreen("BOOTING", "Scanner Online!");
    finger.getParameters();
  } else {
    showScreen("ERROR", "Scanner Offline!", "Check wiring");
    while (1) { delay(1); } // Halt
  }

  printMenu();

  // Initialize BLE
  BLEDevice::init("ESP32 Gate");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  pTxCharacteristic = pService->createCharacteristic(
										CHARACTERISTIC_UUID_TX,
										BLECharacteristic::PROPERTY_NOTIFY
									);
                      
  pTxCharacteristic->addDescriptor(new BLE2902());
  
  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
											 CHARACTERISTIC_UUID_RX,
											 BLECharacteristic::PROPERTY_WRITE
										 );

  pRxCharacteristic->setCallbacks(new MyCallbacks());
  pService->start();
  pServer->getAdvertising()->start();
  showScreen("SYSTEM READY", "BLE Started", "Waiting for input...");
  delay(1000);
}

void loop() {
  // Handle Web Server Requests
  server.handleClient();

  // Handle chunked BLE data timeout
  if (bleReceiving && (millis() - bleDataTime > 1000)) {
    bleCommand.trim();
    bleCommandPending = true;
    bleReceiving = false;
  }

  if (bleCommandPending) {
    Serial.println("BLE Command Received: " + bleCommand);
    if (bleCommand.startsWith("CMD:LIST_FILES")) {
      File root = SD.open("/");
      root.rewindDirectory();
      File file = root.openNextFile();
      while(file){
        if(!file.isDirectory()){
          String fname = String(file.name());
          if (fname.endsWith(".csv")) {
            String msg = "FILE:" + fname + "\n";
            // Safely chunk the filename in case it exceeds 20 bytes
            int offset = 0;
            while (offset < msg.length()) {
              int chunk = msg.length() - offset;
              if (chunk > 20) chunk = 20;
              String part = msg.substring(offset, offset + chunk);
              pTxCharacteristic->setValue((uint8_t*)part.c_str(), part.length());
              pTxCharacteristic->notify();
              offset += chunk;
              delay(30);
            }
          }
        }
        file = root.openNextFile();
      }
      String eofMsg = "EOF:LIST\n";
      pTxCharacteristic->setValue((uint8_t*)eofMsg.c_str(), eofMsg.length());
      pTxCharacteristic->notify();
    } 
    else if (bleCommand.startsWith("CMD:GET_FILE:")) {
      String filename = bleCommand.substring(13); // remove "CMD:GET_FILE:"
      if (!filename.startsWith("/")) {
        filename = "/" + filename;
      }
      File file = SD.open(filename);
      if (file) {
        String buffer = "";
        while (file.available()) {
          char c = file.read();
          buffer += c;
          // IMPORTANT: MTU size limit is 20 bytes!
          if (buffer.length() >= 20) {
            pTxCharacteristic->setValue((uint8_t*)buffer.c_str(), buffer.length());
            pTxCharacteristic->notify();
            buffer = "";
            delay(30); // Small delay to avoid dropping packets
          }
        }
        if (buffer.length() > 0) {
            pTxCharacteristic->setValue((uint8_t*)buffer.c_str(), buffer.length());
            pTxCharacteristic->notify();
            delay(30);
        }
        file.close();
      } else {
        Serial.println("❌ Failed to open file via BLE: " + filename);
      }
      String eofMsg = "EOF:FILE\n";
      pTxCharacteristic->setValue((uint8_t*)eofMsg.c_str(), eofMsg.length());
      pTxCharacteristic->notify();
    }
    else if (bleCommand.startsWith("CMD:PUT_FILE")) {
      uploadFileName = "/registered_student.csv";
      
      Serial.println("Starting file upload to: " + uploadFileName);
      
      // Open file for writing (overwrite if exists)
      uploadFile = SD.open(uploadFileName, FILE_WRITE);
      if (uploadFile) {
        isReceivingFile = true;
        String ack = "READY_TO_RECEIVE\n";
        pTxCharacteristic->setValue((uint8_t*)ack.c_str(), ack.length());
        pTxCharacteristic->notify();
      } else {
        Serial.println("❌ Failed to open file for writing: " + uploadFileName);
        String err = "ERR:FILE_OPEN\n";
        pTxCharacteristic->setValue((uint8_t*)err.c_str(), err.length());
        pTxCharacteristic->notify();
      }
    }
    
    bleCommandPending = false;
  }

  // Handle BLE connection states
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); // give the bluetooth stack the chance to get things ready
      pServer->startAdvertising(); // restart advertising
      Serial.println("BLE start advertising");
      oldDeviceConnected = deviceConnected;
  }
  // connecting
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
  }

  // char key = customKeypad.getKey();
  char key = 0;

  if (Serial.available()) {
    key = Serial.read();
    
    // Treat newline or carriage return as the '#' (Enter) key
    if (key == '\n' || key == '\r') {
      if (currentInput.length() > 0) {
        key = '#';
      } else {
        key = 0; // Ignore empty newlines
      }
    }
  }

  if (key) {
    if (key == '#') {
      // '#' acts as Enter key
      String input = currentInput;
      currentInput = ""; // Clear buffer
      Serial.println();  // Move to next line in Serial Monitor

      if (currentState == STATE_MENU) {
        if (input == "1") {
          currentState = STATE_ENROLL_WAIT_ID;
          showScreen("ENROLL", "Enter ID on keypad", "Press # to confirm");
        } 
        else if (input == "2") {
          currentState = STATE_ATTENDANCE_MODE;
          showScreen("ATTENDANCE", "Place Finger...", "Press * to cancel");
        }
        else if (input == "3") {
          currentState = STATE_DOWNLOAD_TEMPLATE;
          showScreen("VIEW TEMPLATE", "Enter ID on keypad", "Press # to confirm");
        }
        else if (input == "4") {
          showScreen("CLEAR DB", "Deleting all...", "Please wait");
          if (finger.emptyDatabase() == FINGERPRINT_OK) {
            showScreen("CLEAR DB", "DB Cleared!", "Checking SD backup");
            if (SD.exists("/templates.csv")) {
              if (SD.remove("/templates.csv")) {
                showScreen("CLEAR DB", "DB & SD Cleared!");
              } else {
                showScreen("ERROR", "Failed clearing SD!");
              }
            }
          } else {
            showScreen("ERROR", "Failed to clear DB!");
          }
          delay(2000);
          printMenu();
        }
        else if (input.length() > 0) {
          showScreen("ERROR", "Invalid Option!", "Press 1,2,3, or 4");
          delay(1500);
          printMenu();
        }
      } 
      else if (currentState == STATE_DOWNLOAD_TEMPLATE) {
        int id = input.toInt();
        if (id >= 1 && id <= 1000) {
          downloadFingerprintTemplate(id);
          currentState = STATE_MENU;
          printMenu();
        } else if (input.length() > 0) {
          showScreen("ERROR", "Invalid ID!", "Try again, press #");
        }
      }
      else if (currentState == STATE_ENROLL_WAIT_ID) {
        int id = input.toInt();
        if (id >= 1 && id <= 1000) {
          if (isStudentRegistered(id)) {
            pendingEnrollID = id;
            getFingerprintEnroll(pendingEnrollID);
          } else {
            showScreen("ERROR", "Access Denied!", "ID not in CSV", "ID #" + String(id));
            delay(2000);
          }
          // After enrollment finishes (success or fail), go back to menu
          currentState = STATE_MENU;
          printMenu();
        } else if (input.length() > 0) {
          showScreen("ERROR", "Invalid ID!", "Must be 1-1000", "Try again, press #");
        }
      }
    } 
    else if (key == '*') {
      // '*' acts as Cancel/Backspace
      if (currentInput.length() > 0) {
        // Backspace
        currentInput.remove(currentInput.length() - 1);
        Serial.print("\b \b"); // Erase character from Serial Monitor
        
        // Update screen
        if (currentState == STATE_ENROLL_WAIT_ID) {
          showScreen("ENROLL", "Enter ID on keypad", "ID: " + currentInput);
        } else if (currentState == STATE_DOWNLOAD_TEMPLATE) {
          showScreen("VIEW TEMPLATE", "Enter ID on keypad", "ID: " + currentInput);
        }
      } else {
        // If buffer is empty, '*' acts as Cancel/Go back
        if (currentState == STATE_ATTENDANCE_MODE) {
          showScreen("INFO", "Stopping Attendance");
          delay(1000);
          currentState = STATE_MENU;
          printMenu();
        }
      }
    } 
    else {
      // Append number/letter to the buffer
      currentInput += key;
      Serial.print(key); // Echo character to Serial Monitor
      
      // Update screen
      if (currentState == STATE_ENROLL_WAIT_ID) {
        showScreen("ENROLL", "Enter ID on keypad", "ID: " + currentInput);
      } else if (currentState == STATE_DOWNLOAD_TEMPLATE) {
        showScreen("VIEW TEMPLATE", "Enter ID on keypad", "ID: " + currentInput);
      }
    }
  } 
  // If in attendance mode, constantly scan the sensor
  if (currentState == STATE_ATTENDANCE_MODE) {
    checkAttendance();
    delay(50); // Small delay to prevent spamming the sensor
  }
}

// ---------------------------------------------------------
// Helper Functions
// ---------------------------------------------------------

void printMenu() {
  showScreen("MAIN MENU", "[1] Enroll", "[2] Attendance", "[3] DL [4] Clear");
}

void clearSerialBuffer() {
  while (Serial.available()) {
    Serial.read();
  }
}

// Scans the glass and checks for matches in the database
void checkAttendance() {
  uint8_t p = finger.getImage();
  
  // If no finger is pressed, just exit quietly
  if (p == FINGERPRINT_NOFINGER) return; 
  
  // If there's an imaging error, just silently fail so we can instantly take another picture
  if (p != FINGERPRINT_OK) return;

  // Convert the image
  p = finger.image2Tz();
  if (p != FINGERPRINT_OK) {
    Serial.print("?"); // Print a question mark if the picture was blurry or they moved
    return;
  }

  // Search the database
  p = finger.fingerSearch();
  if (p == FINGERPRINT_OK) {
    showScreen("ATTENDANCE", "Logged: ID #" + String(finger.fingerID), "Confidence: " + String(finger.confidence));
    
    // Log attendance to the daily CSV file on SD card
    logAttendance(finger.fingerID);
    
    // Wait for them to remove their finger so it doesn't log 10 times a second!
    while (finger.getImage() != FINGERPRINT_NOFINGER) {
      delay(100);
    }
    
    // Add a 1 second delay before the next scan can happen, as requested!
    delay(1000); 
    showScreen("ATTENDANCE", "Place Finger...", "Press * to cancel");
  } 
  else if (p == FINGERPRINT_NOTFOUND) {
    showScreen("ATTENDANCE", "Not Found!", "Try again...");
    delay(1000);
    showScreen("ATTENDANCE", "Place Finger...", "Press * to cancel");
  } 
  else {
    showScreen("ERROR", "Scan failed", "Code: 0x" + String(p, HEX));
    
    // CRITICAL RECOVERY: If the sensor glitches, flush the serial buffer to fix it automatically!
    while(serialPort.available()) {
      serialPort.read();
    }
    
    // Wait for finger to be removed to stop spamming
    while (finger.getImage() != FINGERPRINT_NOFINGER) { delay(100); }
    delay(1000); // Wait a second before trying again
    showScreen("ATTENDANCE", "Place Finger...", "Press * to cancel");
  }
}

// Handles the 2-step enrollment process for a specific ID with continuous retry on picture 2
uint8_t getFingerprintEnroll(uint16_t id) {
  int p = -1;
  showScreen("ENROLL ID #" + String(id), "Place finger...");
  
  // Wait for first scan
  while (p != FINGERPRINT_OK) {
    p = finger.getImage();
    if (p == FINGERPRINT_OK) {
      showScreen("ENROLL ID #" + String(id), "Image 1 Taken!", "Remove finger...");
    } else if (p != FINGERPRINT_NOFINGER) {
      showScreen("ERROR", "Imaging error", "Code: " + String(p));
      delay(1500);
      return p;
    }
  }

  // Convert first scan
  p = finger.image2Tz(1);
  if (p != FINGERPRINT_OK) {
    showScreen("ERROR", "Convert error 1");
    delay(1500);
    return p;
  }
  
  delay(2000);
  
  // Wait until finger is completely removed
  p = 0;
  while (p != FINGERPRINT_NOFINGER) {
    p = finger.getImage();
  }
  
  showScreen("ENROLL ID #" + String(id), "Place SAME finger");
  
  bool modelCreated = false;
  
  // Continuous Loop for Image 2! It will keep taking pictures until it perfectly matches Image 1
  while (!modelCreated) {
    p = -1;
    // Wait for second scan
    while (p != FINGERPRINT_OK) {
      p = finger.getImage();
    }

    // Convert second scan
    p = finger.image2Tz(2);
    if (p != FINGERPRINT_OK) {
      continue; // Skip the rest of the loop and try again!
    }
    
    // Create model comparing the two scans
    p = finger.createModel();
    if (p == FINGERPRINT_OK) {
      showScreen("ENROLL ID #" + String(id), "Matched perfectly!");
      modelCreated = true; // Break out of the continuous loop!
    } else {
      showScreen("ENROLL ID #" + String(id), "Did not match!", "Lift and try again");
      // Wait for them to lift their finger before taking the next picture
      while (finger.getImage() != FINGERPRINT_NOFINGER) { delay(100); }
      showScreen("ENROLL ID #" + String(id), "Place SAME finger");
    }   
  }
  
  // Save model to sensor memory
  p = finger.storeModel(id);
  if (p == FINGERPRINT_OK) {
    showScreen("SUCCESS", "ID #" + String(id) + " saved!");
    // Download template from sensor and save to SD card
    saveTemplateToSD(id);
    delay(2000);
  } else {
    showScreen("ERROR", "Save failed!");
    delay(2000);
    return p;
  }   
  
  return FINGERPRINT_OK;
}

// Downloads the raw hex data of a fingerprint template from the sensor memory
void downloadFingerprintTemplate(uint16_t id) {
  Serial.println("------------------------------------");
  Serial.print("Loading fingerprint ID #"); Serial.println(id);
  
  uint8_t p = finger.loadModel(id);
  if (p != FINGERPRINT_OK) {
    Serial.println("❌ Failed to load model (Is this ID empty?)");
    return;
  }
  
  Serial.println("Requesting template transfer from sensor...");
  p = finger.getModel();
  if (p != FINGERPRINT_OK) {
    Serial.println("❌ Failed to transfer model!");
    return;
  }
  
  Serial.println("\n--- RAW FINGERPRINT DATA (HEX) ---");
  
  uint32_t starttime = millis();
  int count = 0;
  
  // The sensor will stream the data packets over serial.
  // We just read everything it sends for the next 2 seconds!
  while ((millis() - starttime) < 2000) {
    if (serialPort.available()) {
      uint8_t c = serialPort.read();
      if (c < 16) Serial.print("0");
      Serial.print(c, HEX);
      Serial.print(" ");
      count++;
      if (count % 16 == 0) Serial.println(); // New line every 16 bytes
    }
  }
  
  Serial.println("\n------------------------------------");
  Serial.print(count); Serial.println(" bytes of raw data extracted.");
}

// Downloads the raw fingerprint template from sensor memory and saves to SD card as a CSV row
void saveTemplateToSD(uint16_t id) {
  Serial.print("Downloading template to SD card for ID #"); Serial.println(id);
  
  uint8_t p = finger.loadModel(id);
  if (p != FINGERPRINT_OK) {
    Serial.println("❌ Failed to load model for SD backup.");
    return;
  }
  
  p = finger.getModel();
  if (p != FINGERPRINT_OK) {
    Serial.println("❌ Failed to transfer model for backup!");
    return;
  }
  
  String filename = "/templates.csv";
  
  // On ESP32, FILE_WRITE overwrites the file. We MUST use FILE_APPEND to add new rows!
  File dataFile = SD.open(filename, FILE_APPEND);
  if (!dataFile) {
    Serial.println("❌ Error opening " + filename + " for writing.");
    return;
  }
  
  // Write the User ID and a comma to start the CSV row
  dataFile.print(id);
  dataFile.print(",");
  
  uint32_t starttime = millis();
  int count = 0;
  
  // The sensor will stream the data packets over serial.
  // We read them and convert them to readable HEX text before saving
  while ((millis() - starttime) < 2000) {
    if (serialPort.available()) {
      uint8_t c = serialPort.read();
      
      // Print leading zero if needed (e.g. "0F" instead of just "F")
      if (c < 16) {
        dataFile.print("0");
      }
      dataFile.print(c, HEX);
      count++;
    }
  }
  
  // Add a newline at the end so the next user is on a new row
  dataFile.println();
  dataFile.close();
  
  // CRITICAL FIX: Clear any leftover junk from the sensor serial buffer
  // If the sensor sent more bytes than we expected, leaving them in the buffer
  // will crash the NEXT sensor command (causing "Search error")
  while(serialPort.available()) {
    serialPort.read();
  }
  delay(100);
  
  Serial.print("✅ Successfully appended template backup for ID #");
  Serial.print(id);
  Serial.println(" to " + filename + " on SD card!");
}

// Logs the attendance to a daily CSV file on the SD card (e.g. /YYYY-MM-DD.csv)
void logAttendance(uint16_t id) {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) {
    Serial.println("❌ Failed to obtain time for logging! Check Wi-Fi.");
    return;
  }

  // Create date string for filename (e.g., /2026-08-18.csv)
  char dateStr[20];
  strftime(dateStr, sizeof(dateStr), "/%Y-%m-%d.csv", &timeinfo);
  
  // Create time string for the log entry (e.g., 14:35:22)
  char timeStr[15];
  strftime(timeStr, sizeof(timeStr), "%H:%M:%S", &timeinfo);

  // Check if file exists to write header
  bool fileExists = SD.exists(dateStr);

  File file = SD.open(dateStr, FILE_APPEND);
  if (!file) {
    Serial.println("❌ Failed to open daily log file!");
    return;
  }

  if (!fileExists) {
    file.println("User ID,Time"); // Write CSV header for new files
  }

  // Write attendance data
  file.print(id);
  file.print(",");
  file.println(timeStr);
  file.close();

  Serial.print("💾 Logged to SD Card: ");
  Serial.print(dateStr);
  Serial.print(" -> ID ");
  Serial.print(id);
  Serial.print(" at ");
  Serial.println(timeStr);

  // Now log the raw scanned template to the secondary CSV file
  logScannedTemplate(id, &timeinfo);
}

// Downloads the template that was JUST scanned (currently in sensor's CharBuffer)
// and saves it to a separate daily CSV file
void logScannedTemplate(uint16_t id, struct tm* timeinfo) {
  char scansFilename[30];
  strftime(scansFilename, sizeof(scansFilename), "/%Y-%m-%d_scans.csv", timeinfo);
  
  char timeStr[15];
  strftime(timeStr, sizeof(timeStr), "%H:%M:%S", timeinfo);
  
  Serial.println("Downloading newly scanned template to SD card...");
  
  // CRITICAL: We DO NOT call finger.loadModel(id)! 
  // We want the live scan that was just placed into CharBuffer 1 by finger.image2Tz()
  uint8_t p = finger.getModel();
  if (p != FINGERPRINT_OK) {
    Serial.println("❌ Failed to transfer scanned template to ESP32!");
    return;
  }
  
  bool fileExists = SD.exists(scansFilename);
  File dataFile = SD.open(scansFilename, FILE_APPEND);
  if (!dataFile) {
    Serial.println("❌ Error opening " + String(scansFilename) + " for writing.");
    return;
  }
  
  if (!fileExists) {
    dataFile.println("User ID,Time,Scanned Template");
  }
  
  dataFile.print(id);
  dataFile.print(",");
  dataFile.print(timeStr);
  dataFile.print(",");
  
  uint32_t starttime = millis();
  int count = 0;
  
  while ((millis() - starttime) < 2000) {
    if (serialPort.available()) {
      uint8_t c = serialPort.read();
      if (c < 16) dataFile.print("0");
      dataFile.print(c, HEX);
      count++;
    }
  }
  
  dataFile.println();
  dataFile.close();
  
  // Flush leftover data to prevent search errors on next scan
  while(serialPort.available()) {
    serialPort.read();
  }
  delay(100);
  
  Serial.print("✅ Logged scanned template (");
  Serial.print(count);
  Serial.print(" bytes) to ");
  Serial.println(scansFilename);
}

// Checks if a student ID exists in the registered_student.csv file
bool isStudentRegistered(uint16_t id) {
  File file = SD.open("/registered_student.csv");
  if (!file) {
    Serial.println("❌ Could not open /registered_student.csv for verification!");
    return false; // Fail safe: block enrollment if file missing
  }
  
  bool found = false;
  String targetID = String(id);
  
  while (file.available()) {
    String line = file.readStringUntil('\n');
    line.trim();
    if (line.length() == 0) continue; // Skip empty lines
    
    // Split by comma
    int commaIndex = line.indexOf(',');
    String fileID = "";
    if (commaIndex > 0) {
      fileID = line.substring(0, commaIndex);
    } else {
      fileID = line; // If no comma, maybe it's just the ID
    }
    
    if (fileID == targetID) {
      found = true;
      break;
    }
  }
  
  file.close();
  return found;
}
