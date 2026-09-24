# YoelYoestar · Cisco Switch Overview

Widget para Zabbix 7.0 / 7.4 orientado a conmutadores Cisco (Small Business SG200, CBS y conmutadores gestionables). Diseñado para mapear y procesar datos recogidos por SNMP mediante la plantilla **Cisco_SG200-26P** o plantillas estándar de interfaces.

**Versión:** 1.0.0  
**Compatibilidad:** Zabbix 7.0 LTS / 7.4 (Manifest v2.0)

---

## Funciones incluidas

- **Frontal físico interactivo:** Representación visual del chasis con matriz de 24 puertos RJ45 (impares arriba, pares abajo) más bloque dedicado para enlaces combo / SFP (puertos 25 y 26).
- **LEDs de enlace y actividad:** Estado operacional UP/DOWN mediante código de colores e indicación dinámica de parpadeo ante tráfico activo.
- **Rendimiento general:** Lectura de uso de CPU en el último minuto (`rlCpuUtilDuringLastMinute.0`), tiempo de actividad (`uptime`) y agregación de tráfico total de entrada y salida.
- **Modal de gráficos en tiempo real:** Ventana modal con trazado vectorial mediante Canvas HTML5 para examinar el histórico de tráfico de entrada y salida en bps sin librerías externas[cite: 1, 2].
- **Tabla detallada de puertos:** Listado con tasas de transferencia, estado de enlace y acceso directo al histórico de cualquier interfaz.
- **Soporte multiequipo:** Navegación y rotación cíclica automática entre múltiples conmutadores[cite: 1].
- **Adaptación visual nativa:** Integración con los temas claro, oscuro y alto contraste de la interfaz de Zabbix[cite: 1].

---

## Instalación

1. Copiar el directorio en la siguiente ruta:
   ```bash
   cp /usr/share/zabbix/modules
   ```
