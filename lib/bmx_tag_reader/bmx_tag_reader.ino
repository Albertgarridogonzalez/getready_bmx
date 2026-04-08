#include <Arduino.h>

/**
 * BMX Card Reader Lite - ESP32 Secundario
 * Este código lee etiquetas por RS232 y muestra solo los últimos 6 dígitos.
 */

// ================== CONFIGURACIÓN UART LECTOR ==================
HardwareSerial READER(2);
static const int READER_RX = 18;
static const int READER_TX = 17;
static const uint32_t READER_BAUD = 115200;

uint8_t rxbuf[512];
int rxlen = 0;

void parseFrame(const uint8_t* f, int n) {
  if (n < 6 || f[0] != 0xCF) return;
  uint16_t cmd = (f[2] << 8) | f[3];
  uint8_t dLen = f[4];
  if (5 + dLen + 2 > n) return;
  const uint8_t* d = &f[5];

  // cmd == 0x0001 es la respuesta de inventario que contiene el EPC
  if (cmd == 0x0001 && dLen >= 7) {
    uint8_t epcLen = d[5];
    if (6 + epcLen <= dLen) {
      String epc = "";
      for (int i = 0; i < epcLen; i++) {
        char b[3];
        sprintf(b, "%02X", d[6 + i]);
        epc += b;
      }
      
      // Mostrar solo los últimos 6 dígitos
      if (epc.length() >= 6) {
        String lastSix = epc.substring(epc.length() - 6);
        Serial.printf("Etiqueta: %s\n", lastSix.c_str());
      } else {
        Serial.printf("Etiqueta: %s\n", epc.c_str());
      }
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
    for (int i = 0; i < rxlen; i++) { 
      if (rxbuf[i] == 0xCF) { start = i; break; } 
    }
    
    if (start < 0) { rxlen = 0; break; }
    if (start > 0) { 
      memmove(rxbuf, rxbuf + start, rxlen - start); 
      rxlen -= start; 
    }
    
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

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  // Inicializar comunicación con el lector RS232
  READER.begin(READER_BAUD, SERIAL_8N1, READER_RX, READER_TX);
  
  Serial.println("\n--- BMX TAG READER LITE (ESCLAVO) ---");
  Serial.println("Esperando etiquetas...");
}

void loop() {
  pumpReader();
  delay(1);
}
