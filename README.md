# Smart Fingerprint-Based Attendance and Data Management System

## Overview
The **Smart Fingerprint-Based Attendance System** is a low-cost, standalone, secure, and automated attendance solution built around an ESP32. It combines biometric authentication, local data storage, accurate time tracking, and wireless data management to seamlessly track student attendance.

The main idea is to identify students using their unique fingerprints and automatically record their attendance along with the exact time. This reduces manual work and prevents repeated or incorrect attendance entries.

## Hardware Components
- **ESP32 Microcontroller**: Serves as the central processing unit, providing Wi-Fi and Bluetooth connectivity.
- **Fingerprint Sensor (R307/Similar)**: Enrolls and identifies students based on their unique fingerprints.
- **SD Card Module**: Stores attendance records locally in CSV format, ensuring data is not lost and can be accessed without a network.
- **OLED Display (SH1106G)**: Provides visual feedback on system status, enrollment steps, and successful/failed scans.
- **LED Indicators**: Bi-color (Red/Green) LEDs offer immediate visual confirmation of authentication status.

## Software Architecture
The system consists of two main software components:

### 1. ESP32 Firmware (C++)
The firmware manages the hardware peripherals and handles the core logic of the attendance system:
- **Enrollment Mode**: Registers new fingerprints and saves them securely in the sensor's memory, backing up templates to the SD card.
- **Attendance Mode**: Actively scans for fingerprints, cross-references them with enrolled users, and logs successful matches to a daily CSV file on the SD card with accurate timestamps via NTP.
- **Web Server**: Hosts a local web page over Wi-Fi, allowing users to download the CSV attendance logs directly from the SD card.
- **BLE Server**: Implements Nordic UART Service (NUS) to facilitate wireless data transfer (uploading/downloading files) to a companion mobile application.

### 2. Companion Mobile Application (Flutter)
A cross-platform mobile application that interfaces with the ESP32 via Bluetooth Low Energy (BLE) and Firebase:
- **Device Synchronization**: Connects to the ESP32 via BLE to fetch scanned templates and attendance logs wirelessly without removing the SD card.
- **Adaptive Template Retraining**: Automatically analyzes recent successful fingerprint scans, compares them with the original template, and updates the ESP32's stored template to improve future scan accuracy.
- **Data Management**: Syncs attendance data to Firebase for centralized access, reporting, and management.
- **User Interface**: Provides an intuitive dashboard for teachers and admins to view student records, attendance reports, and manage hardware configurations.

## Features
- **Standalone Operation**: Functions completely offline for scanning and logging using the SD card and RTC/NTP time.
- **Wireless Syncing**: Eliminates the need to physically remove the SD card by utilizing a local Web Server and BLE for file transfers.
- **Adaptive Biometric Accuracy**: The mobile app continuously optimizes templates to prevent false rejections over time.
- **Instant Feedback**: OLED display and Red/Green LEDs provide immediate confirmation of actions.

## Setup & Installation

### Firmware Deployment
1. Open the `.ino` file in the Arduino IDE.
2. Ensure you have installed the required libraries: `Adafruit Fingerprint Sensor Library`, `Adafruit SH110X`, `BLEDevice`.
3. Update the Wi-Fi credentials (`ssid` and `password`) in the code.
4. Flash the code to your ESP32.

### Mobile App Deployment
1. Ensure Flutter is installed and configured on your machine.
2. Run `flutter pub get` to install dependencies.
3. Run `flutter build apk --release` to generate the release APK for Android.
4. Install the generated APK on your Android device.

## Usage
- **Boot Up**: The ESP32 will connect to Wi-Fi, sync time with NTP, and initialize the BLE server and web server.
- **Serial/Keypad Menu**: Choose between Enroll (1), Attendance (2), View Raw (3), or Clear Database (4).
- **Mobile Sync**: Open the app, connect to "ESP32 Gate" via Bluetooth, and synchronize records or update optimized templates.
