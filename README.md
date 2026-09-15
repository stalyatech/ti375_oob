# ti375_oob
Efinix TI375C529 Development kit design

## Çalışma çıktıları

- Sentez, yerleştirme ve bitstream akışı logları: `syn/logs/` (git dışı).
- Board bring-up logları (OpenOCD, UART yakalamaları): `embedded_sw/logs/` (git dışı).
- Simülasyon derleme çıktıları ve dalga dosyaları: `sim/<blok>/sim_build/` (git dışı).

Kök dizine log veya ara çıktı bırakılmaz; `efx_run`, OpenOCD ve simülatör çağrılarında çıktı yönlendirmesi bu dizinlere yapılır.
