// ================== MODOS DE CONEXIÓN ==================
#define TINY_GSM_MODEM_SIM800
#define TINY_GSM_USE_GPRS true
#define TINY_GSM_USE_WIFI false

// ======================================================
// INCLUDES
// ======================================================
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <Update.h>
#include "esp_bt.h"
#include <map>

#include <TinyGsmClient.h>
#include <ArduinoHttpClient.h> 

#include <FS.h>
#include <SPIFFS.h>
#include <time.h>
#include <esp_task_wdt.h>

// ================== BLE & PREFERENCES ==================
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <Preferences.h>

// ================== CONFIG VERSION & OTAs ==================
const char* CURRENT_VERSION = "1.0.5_BMX"; 
const char* FIRMWARE_URL = "https://raw.githubusercontent.com/Albertgarridogonzalez/ch_zaorit_rfid/main/firmware.bin";

// ================== BMX CONFIGURATION ==================
const int TRIGGER_PIN = 32; // Pulsor para empezar carrera
const unsigned long RACE_DURATION_MS = 20000; // 20 segundos
bool raceActive = false;
unsigned long raceStartTime = 0;

struct TagData {
  int rssi;
  unsigned long bestMs; // Milisegundos desde el inicio de la carrera
};
std::map<String, TagData> sessionTags;

// ✅ CLOUD FUNCTION URL
const char* BMX_FUNCTION_URL = "https://us-central1-getready-bmx.cloudfunctions.net/bmxRaceTiming";

// ================== BLE CONFIG ==================
#define BLE_NAME "BMX_RACE_TIMING"
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

const unsigned long BLE_TIMEOUT_MS = 30000;
bool bleActive = true;
bool deviceConnected = false;
bool bleFinished = false;

BLEServer* pServer = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
Preferences preferences;

// ================== CONFIG WIFI / FIREBASE ==================
const char* DEFAULT_WIFI_SSID = "ALOHA_TERRAZA";
const char* DEFAULT_WIFI_PASS = "LuaAragorn68";

String wifi_ssid = DEFAULT_WIFI_SSID;
String wifi_pass = DEFAULT_WIFI_PASS;

const char* DEFAULT_DEVICE_ID = "BMX_RACE_TIMING";
String device_id = DEFAULT_DEVICE_ID;

const char* DEFAULT_DEVICE_NAME = "Mataró Gates";
String device_name = DEFAULT_DEVICE_NAME;

const char* APN = "www";
const char* APN_USER = "";
const char* APN_PASS = "";

// ================== UART CF661 ==================
HardwareSerial READER(2);
static const int READER_RX = 18;
static const int READER_TX = 17;
static const uint32_t READER_BAUD = 115200;

// ================== SIM800L ==================
//#define MODEM_RX 26
#define MODEM_RX 26
#define MODEM_TX 27
#define MODEM_PWKEY 4
#define MODEM_RST 5
#define MODEM_POWER_ON 23

HardwareSerial SerialAT(1);
TinyGsm modem(SerialAT);
TinyGsmClient gsmClient(modem);
bool usaSIM = false;

uint8_t rxbuf[512];
int rxlen = 0;
unsigned long bootBlockTime = 0;

// ================== UTIL — ISO TIME ==================
String toISO8601(time_t t) {
  char buf[32];
  strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", gmtime(&t));
  return String(buf);
}

void syncTimeNTP() {
  Serial.print("⏱️ Sincronizando hora (NTP)");
  configTime(0, 0, "pool.ntp.org");
  time_t now = 0;
  unsigned long start = millis();
  while (now < 100000 && millis() - start < 15000) {
    now = time(nullptr);
    Serial.print(".");
    delay(500);
    yield();
    esp_task_wdt_reset();
  }
  if (now < 100000) Serial.println("\n⚠️ Error al sincronizar hora");
  else Serial.printf("\n⏱️ UTC: %s\n", toISO8601(now).c_str());
}

// ================== SIM HELPERS ==================
void encenderSIM() {
  pinMode(MODEM_PWKEY, OUTPUT);
  pinMode(MODEM_RST, OUTPUT);
  pinMode(MODEM_POWER_ON, OUTPUT);
  digitalWrite(MODEM_PWKEY, LOW);
  digitalWrite(MODEM_RST, HIGH);
  digitalWrite(MODEM_POWER_ON, HIGH);
  delay(1000);
  digitalWrite(MODEM_PWKEY, HIGH);
  delay(3500);
}

bool detectarSIM() {
  encenderSIM();
  SerialAT.begin(115200, SERIAL_8N1, MODEM_RX, MODEM_TX);
  delay(500);
  while (SerialAT.available()) SerialAT.read();
  SerialAT.println("AT+CGSN");
  String resp;
  unsigned long t0 = millis();
  while (millis() - t0 < 2000) { while (SerialAT.available()) resp += (char)SerialAT.read(); }
  int digits = 0;
  for (char c : resp) { if (isdigit((unsigned char)c)) digits++; }
  bool ok = (digits >= 12);
  Serial.println(ok ? "✅ SIM detectada" : "❌ SIM NO detectada");
  return ok;
}

bool conectarGPRS() {
  Serial.println("📡 Iniciando GPRS...");
  modem.restart();
  delay(1000);
  esp_task_wdt_reset();
  unsigned long t0 = millis();
  while (millis() - t0 < 30000) {
    if (modem.isNetworkConnected()) break;
    delay(500);
    esp_task_wdt_reset();
  }
  bool ok = modem.gprsConnect(APN, APN_USER, APN_PASS);
  Serial.println(ok ? "✅ GPRS conectado" : "❌ Error en GPRS");
  return ok;
}

// ================== BLE CONFIG ==================
String extractJsonValue(const String& json, const String& key) {
  String pattern = "\"" + key + "\":\"";
  int idx = json.indexOf(pattern);
  if (idx < 0) return "";
  idx += pattern.length();
  int end = json.indexOf("\"", idx);
  if (end < 0) return "";
  return json.substring(idx, end);
}

void loadDeviceIdFromNVS() {
  preferences.begin("wifi_config", true);
  String storedDev = preferences.getString("device_id", "");
  String storedName = preferences.getString("device_name", "");
  preferences.end();
  if (storedDev.length() > 0) device_id = storedDev;
  if (storedName.length() > 0) device_name = storedName;
}

class BLECallbacksServer : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override { deviceConnected = true; }
  void onDisconnect(BLEServer* pServer) override {
    deviceConnected = false;
    if (millis() < BLE_TIMEOUT_MS) pServer->getAdvertising()->start();
  }
};

class BLECallbacksCharacteristic : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    String json = characteristic->getValue();
    if (json.length() == 0) return;
    String newSSID = extractJsonValue(json, "ssid");
    String newPASS = extractJsonValue(json, "password");
    String newESP32 = extractJsonValue(json, "esp32Id");
    String newDeviceName = extractJsonValue(json, "deviceName");
    preferences.begin("wifi_config", false);
    if (newSSID.length() > 0) { preferences.putString("ssid", newSSID); preferences.putString("pass", newPASS); }
    if (newESP32.length() > 0) preferences.putString("device_id", newESP32);
    if (newDeviceName.length() > 0) preferences.putString("device_name", newDeviceName);
    preferences.end();
    delay(1000);
    ESP.restart();
  }
};

void initBLE() {
  BLEDevice::init(BLE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new BLECallbacksServer());
  BLEService* pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE);
  pCharacteristic->setCallbacks(new BLECallbacksCharacteristic());
  pService->start();
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->start();
  Serial.println("🔵 Modo de configuración BLE activo (30s)");
}

// ================== BMX UPLOAD ==================
void uploadRaceResults() {
  if (sessionTags.empty()) { 
    Serial.println("\nℹ️ No se detectaron pilotos en esta carrera."); 
    return; 
  }

  Serial.println("\n========================================");
  Serial.println("📊 RESUMEN DE CARRERA (Picos de señal)");
  Serial.println("----------------------------------------");
  for (auto const& [rfid, data] : sessionTags) {
    Serial.printf("🆔 RFID: %s | 📶 RSSI Máx: %d | ⏱️ Tiempo: %lu ms\n", 
                  rfid.c_str(), data.rssi, data.bestMs);
  }
  Serial.println("========================================\n");

  // Check connectivity
  if (WiFi.status() != WL_CONNECTED && usaSIM && !modem.isGprsConnected()) {
    conectarGPRS();
  }

  bool conectado = (WiFi.status() == WL_CONNECTED) || (usaSIM && modem.isGprsConnected());
  
  if (!conectado) {
    Serial.println("❌ ERROR: Sin conexión (WiFi/SIM). No se pueden subir los datos.");
    return;
  }

  Serial.printf("📤 Subiendo %d resultados...\n", sessionTags.size());

  for (auto const& [rfid, data] : sessionTags) {
    // Enviamos el RFID, el tiempo transcurrido (ms) y el RSSI
    String json = "{\"rfid\":\"" + rfid + "\",\"t_ms\":" + String(data.bestMs) + ",\"rssi\":" + String(data.rssi) + ",\"deviceId\":\"" + device_name + "\"}";
    
    Serial.println("----------------------------------------");
    Serial.print("➡️ ENVIANDO: ");
    Serial.println(json);

    if (WiFi.status() == WL_CONNECTED) {
      WiFiClientSecure client; client.setInsecure();
      HTTPClient http;
      http.begin(client, BMX_FUNCTION_URL);
      http.addHeader("Content-Type", "application/json");
      int code = http.POST(json);
      String resp = http.getString();
      if (code == 200) Serial.printf("🌍 Resp. WiFi OK: %s\n", resp.c_str());
      else Serial.printf("🌍 Error WiFi %d: %s\n", code, resp.c_str());
      http.end();
    } else if (usaSIM && modem.isGprsConnected()) {
      // Intentamos HTTPS via SIM800 es complejo, usamos el host y ruta para el HttpClient
      // pero ojo: SIM800 normal NO hace HTTPS en puerto 80. 
      // Si la función requiere HTTPS, esto podría fallar.
      String host = "us-central1-getready-bmx.cloudfunctions.net";
      String path = "/bmxRaceTiming";
      HttpClient http(gsmClient, host, 80); // Muchos Cloud Functions no aceptan puerto 80 directamente
      http.post(path, "application/json", json);
      int code = http.responseStatusCode();
      String resp = http.responseBody();
      if (code == 200) Serial.printf("🌍 Resp. SIM OK: %s\n", resp.c_str());
      else Serial.printf("🌍 Error SIM %d: %s\n", code, resp.c_str());
      http.stop();
    }
  }
  Serial.println("----------------------------------------");
  Serial.println("✅ Proceso finalizado.");
}

// ================== RFID LOGIC ==================
void handleRaceEPC(const String& epc, int rssi) {
  if (!raceActive) return;
  TagData& data = sessionTags[epc];
  
  // Si encontramos un RSSI más fuerte, guardamos ese momento como el cruce
  if (data.rssi == 0 || rssi > data.rssi) {
    data.rssi = rssi;
    data.bestMs = millis() - raceStartTime;
    Serial.printf("🚴 Tag %s | RSSI Máx: %d | ⏱️ T+%lu ms\n", epc.c_str(), rssi, data.bestMs);
  }
}

void parseFrame(const uint8_t* f, int n) {
  if (n < 6 || f[0] != 0xCF) return;
  uint16_t cmd = (f[2] << 8) | f[3];
  uint8_t dLen = f[4];
  if (5 + dLen + 2 > n) return;
  const uint8_t* d = &f[5];

  if (cmd == 0x0001 && dLen >= 7) {
    uint8_t epcLen = d[5];
    if (6 + epcLen <= dLen) {
      String epc;
      for (int i = 0; i < epcLen; i++) {
        char b[3]; sprintf(b, "%02X", d[6 + i]); epc += b;
      }
      
      // Intentamos capturar el RSSI del byte siguiente si está disponible
      // Algunos lectores Chafon añaden el RSSI como un byte extra al final del EPC
      int rssi = 0;
      if (dLen > (6 + epcLen)) {
          rssi = d[6 + epcLen];
      } else {
          // Si no detectamos RSSI real, asignamos un valor base para que pinte algo
          rssi = 10; 
      }
      handleRaceEPC(epc, rssi);
    }
  }
}

void pumpReader() {
  while (READER.available()) {
    uint8_t b = READER.read();
    if (rxlen < (int)sizeof(rxbuf)) rxbuf[rxlen++] = b;
  }
  bool again;
  do {
    again = false;
    if (rxlen < 6) break;
    int start = -1;
    for (int i = 0; i < rxlen; i++) { if (rxbuf[i] == 0xCF) { start = i; break; } }
    if (start < 0) { rxlen = 0; break; }
    if (start > 0) { memmove(rxbuf, rxbuf + start, rxlen - start); rxlen -= start; }
    if (rxlen < 6) break;
    uint8_t len = rxbuf[4];
    int frameTotal = 5 + len + 2;
    if (frameTotal <= rxlen) {
      parseFrame(rxbuf, frameTotal);
      memmove(rxbuf, rxbuf + frameTotal, rxlen - frameTotal);
      rxlen -= frameTotal;
      again = true;
    }
  } while (again);
}

// ================== SETUP / LOOP ==================
void setup() {
  Serial.begin(115200);
  pinMode(TRIGGER_PIN, INPUT_PULLUP);
  
  esp_task_wdt_config_t twdt_config = {
      .timeout_ms = 60000,
      .idle_core_mask = (1 << portNUM_PROCESSORS) - 1,
      .trigger_panic = true,
  };
  
  // En ESP32 core nuevo, el watchdog suele estar ya iniciado.
  if (esp_task_wdt_reconfigure(&twdt_config) != ESP_OK) {
    esp_task_wdt_init(&twdt_config);
  }
  esp_task_wdt_add(NULL);

  if (!SPIFFS.begin(true)) Serial.println("❌ Error en SPIFFS");

  initBLE();
}

void initSessionFirebase() {
  String json = "{\"deviceName\":\"" + device_name + "\"}";
  Serial.println("🚀 Init session: " + json);
  String url = "https://us-central1-getready-bmx.cloudfunctions.net/startBmxSession";

  if (WiFi.status() == WL_CONNECTED) {
      WiFiClientSecure client; client.setInsecure();
      HTTPClient http;
      http.begin(client, url);
      http.addHeader("Content-Type", "application/json");
      int code = http.POST(json);
      String resp = http.getString();
      Serial.printf("🌍 Resp Start Session WiFi: %d - %s\n", code, resp.c_str());
      http.end();
  } else if (usaSIM && modem.isGprsConnected()) {
      HttpClient http(gsmClient, "us-central1-getready-bmx.cloudfunctions.net", 80);
      http.post("/startBmxSession", "application/json", json);
      int code = http.responseStatusCode();
      String resp = http.responseBody();
      Serial.printf("🌍 Resp Start Session SIM: %d - %s\n", code, resp.c_str());
      http.stop();
  }
}

void loop() {
  esp_task_wdt_reset();

  if (bleActive && millis() > BLE_TIMEOUT_MS) {
    BLEDevice::deinit(true);
    esp_bt_controller_disable();
    bleActive = false;
    bleFinished = true;
  }

  if (!bleFinished) { delay(10); return; }

  static bool initialized = false;
  if (!initialized) {
    initialized = true;
    // --- Intento de Conexión WiFi ---
    preferences.begin("wifi_config", true);
    wifi_ssid = preferences.getString("ssid", DEFAULT_WIFI_SSID);
    wifi_pass = preferences.getString("pass", DEFAULT_WIFI_PASS);
    device_name = preferences.getString("device_name", DEFAULT_DEVICE_NAME);
    preferences.end();
    
    // Si no se usó loadDeviceIdFromNVS en setup(), cargamos ahora
    loadDeviceIdFromNVS();

    Serial.printf("🌐 Intentando WiFi: %s\n", wifi_ssid.c_str());
    WiFi.begin(wifi_ssid.c_str(), wifi_pass.c_str());
    
    int retries = 0;
    while (WiFi.status() != WL_CONNECTED && retries < 20) { 
      delay(500); 
      Serial.print("."); 
      retries++; 
      esp_task_wdt_reset();
    }

    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("\n✅ WiFi Conectado!");
      syncTimeNTP();
      initSessionFirebase();
    } else {
      Serial.println("\n⚠️ WiFi Fallido. Intentando con SIM...");
      usaSIM = detectarSIM();
      if (usaSIM && conectarGPRS()) {
        initSessionFirebase();
      }
    }
    
    READER.begin(READER_BAUD, SERIAL_8N1, READER_RX, READER_TX);
    Serial.println("🏆 Sistema BMX Listo. Pulsa el pin 32 para empezar la carrera.");
  }

  // --- Start Trigger ---
  if (!raceActive && digitalRead(TRIGGER_PIN) == LOW) {
    delay(50); // debounce
    if (digitalRead(TRIGGER_PIN) == LOW) {
      Serial.println("\n🟢 CARRERA EMPEZADA - Escaneando 20s...");
      raceActive = true;
      raceStartTime = millis();
      sessionTags.clear();
    }
  }

  // --- Race Timer ---
  if (raceActive && (millis() - raceStartTime > RACE_DURATION_MS)) {
    Serial.println("\n🔴 CARRERA FINALIZADA! Subiendo datos...");
    raceActive = false;
    uploadRaceResults();
  }

  pumpReader();
  delay(5);
}
