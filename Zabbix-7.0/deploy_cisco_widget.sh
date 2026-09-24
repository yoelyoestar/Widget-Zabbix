#!/usr/bin/env bash
set -e

# Ruta oficial de módulos en tu servidor
MODULE_DIR="/usr/share/zabbix/modules/CiscoSGOverview"

echo "=========================================================="
echo "==> Desplegando Cisco SG Overview para Zabbix 7.0 / 7.4"
echo "==> Destino: $MODULE_DIR"
echo "=========================================================="

mkdir -p "$MODULE_DIR"/{actions,includes,views,assets/css,assets/js}

# -------------------------------------------------------------
# 1. manifest.json
# -------------------------------------------------------------
cat << 'EOF' > "$MODULE_DIR/manifest.json"
{
  "manifest_version": 2.0,
  "id": "cisco_sg_overview",
  "type": "widget",
  "name": "Cisco SG Overview",
  "namespace": "CiscoSGOverview",
  "version": "1.0.0",
  "author": "YoelYoestar",
  "description": "Panel interactivo para switches Cisco SG200-26P con frontal físico de 26 puertos, métricas de ancho de banda y CPU.",
  "actions": {
    "widget.cisco_sg_overview.view": {
      "class": "WidgetView"
    }
  },
  "widget": {
    "name": "Cisco SG Overview",
    "size": {
      "width": 18,
      "height": 10
    },
    "form_class": "WidgetForm",
    "js_class": "WidgetCiscoSGOverview",
    "use_time_selector": false,
    "refresh_rate": 60
  },
  "assets": {
    "css": ["widget.css"],
    "js": ["class.widget.js"]
  }
}
EOF

# -------------------------------------------------------------
# 2. Widget.php
# -------------------------------------------------------------
cat << 'EOF' > "$MODULE_DIR/Widget.php"
<?php
declare(strict_types = 1);

namespace Modules\CiscoSGOverview;

use Zabbix\Core\CWidget;

class Widget extends CWidget {
    public function getTranslationStrings(): array {
        return [
            'class.widget.js' => [
                'No data' => _('No data')
            ]
        ];
    }
}
EOF

# -------------------------------------------------------------
# 3. includes/WidgetForm.php
# -------------------------------------------------------------
cat << 'EOF' > "$MODULE_DIR/includes/WidgetForm.php"
<?php
declare(strict_types = 1);

namespace Modules\CiscoSGOverview\Includes;

use Zabbix\Widgets\CWidgetField;
use Zabbix\Widgets\CWidgetForm;
use Zabbix\Widgets\Fields\CWidgetFieldCheckBox;
use Zabbix\Widgets\Fields\CWidgetFieldMultiSelectHost;
use Zabbix\Widgets\Fields\CWidgetFieldNumericBox;
use Zabbix\Widgets\Fields\CWidgetFieldTextBox;

class WidgetForm extends CWidgetForm {

    public function addFields(): self {
        return $this
            ->addField(
                (new CWidgetFieldMultiSelectHost('hostids', _('Switches Cisco')))
                    ->setFlags(CWidgetField::FLAG_NOT_EMPTY | CWidgetField::FLAG_LABEL_ASTERISK)
            )
            ->addField(
                (new CWidgetFieldTextBox('uplink_regex', _('Expresión regular Uplinks / Troncales')))
                    ->setDefault('(uplink|trunk|sfp|core|ge25|ge26)')
            )
            ->addField(
                (new CWidgetFieldNumericBox('history_hours', _('Periodo de histórico (horas)')))
                    ->setDefault(12)
            )
            ->addField(
                (new CWidgetFieldCheckBox('enable_auto_rotation', _('Rotación automática de switches')))
                    ->setDefault(0)
            )
            ->addField(
                (new CWidgetFieldNumericBox('page_display_period', _('Tiempo de visualización por switch (segundos)')))
                    ->setDefault(30)
            )
            ->addField(
                (new CWidgetFieldCheckBox('show_overview', _('Mostrar resumen general')))
                    ->setDefault(1)
            )
            ->addField(
                (new CWidgetFieldCheckBox('show_faceplate', _('Mostrar frontal físico de puertos')))
                    ->setDefault(1)
            )
            ->addField(
                (new CWidgetFieldCheckBox('show_interfaces_table', _('Mostrar tabla detallada de puertos')))
                    ->setDefault(1)
            )
            ->addField(
                (new CWidgetFieldNumericBox('cpu_warn', _('Aviso CPU (%)')))
                    ->setDefault(80)
            )
            ->addField(
                (new CWidgetFieldNumericBox('cpu_crit', _('Crítico CPU (%)')))
                    ->setDefault(90)
            )
            ->addField(
                (new CWidgetFieldNumericBox('bandwidth_warn', _('Aviso Utilización Puerto (%)')))
                    ->setDefault(75)
            )
            ->addField(
                (new CWidgetFieldNumericBox('bandwidth_crit', _('Crítico Utilización Puerto (%)')))
                    ->setDefault(90)
            );
    }
}
EOF

# -------------------------------------------------------------
# 4. actions/WidgetView.php
# -------------------------------------------------------------
cat << 'EOF' > "$MODULE_DIR/actions/WidgetView.php"
<?php
declare(strict_types = 1);

namespace Modules\CiscoSGOverview\Actions;

use API;
use CControllerDashboardWidgetView;
use CControllerResponseData;

class WidgetView extends CControllerDashboardWidgetView {

    private array $history = [];

    private const DEFAULTS = [
        'show_overview'          => 1,
        'show_faceplate'         => 1,
        'show_interfaces_table'  => 1,
        'uplink_regex'           => '(uplink|trunk|sfp|core|ge25|ge26)',
        'history_hours'          => 12,
        'enable_auto_rotation'   => 0,
        'page_display_period'    => 30,
        'cpu_warn'               => 80,
        'cpu_crit'               => 90,
        'bandwidth_warn'         => 75,
        'bandwidth_crit'         => 90
    ];

    protected function doAction(): void {
        $settings = array_replace(self::DEFAULTS, $this->fields_values);
        $hostids = array_values(array_unique(array_filter(array_map('strval', $settings['hostids'] ?? []))));

        $payload = [
            'settings'     => $this->publicSettings($settings),
            'hosts'        => [],
            'history'      => [],
            'generated_at' => time()
        ];

        if ($hostids) {
            $payload['hosts'] = $this->getHostsData($hostids, $settings);
            $payload['history'] = $this->history;
        }

        $this->setResponse(new CControllerResponseData([
            'name'    => $this->getInput('name', $this->widget->getName()),
            'payload' => $payload,
            'user'    => ['debug_mode' => $this->getDebugMode()]
        ]));
    }

    private function publicSettings(array $settings): array {
        $result = [];
        foreach (self::DEFAULTS as $key => $default) {
            $value = $settings[$key] ?? $default;
            $result[$key] = is_int($default) ? (int) $value : (string) $value;
        }
        return $result;
    }

    private function getHostsData(array $hostids, array $settings): array {
        $hosts = API::Host()->get([
            'output'           => ['hostid', 'host', 'name', 'status', 'maintenance_status'],
            'hostids'          => $hostids,
            'selectInterfaces' => ['interfaceid', 'ip', 'dns', 'type', 'main', 'available'],
            'preservekeys'     => true
        ]);

        if (!$hosts) {
            $this->history = [];
            return [];
        }

        $items = API::Item()->get([
            'output'    => ['itemid', 'hostid', 'name', 'key_', 'lastvalue', 'lastclock', 'units', 'value_type', 'state'],
            'hostids'   => array_keys($hosts),
            'filter'    => ['status' => 0],
            'webitems'  => true
        ]);

        $by_host = [];
        $history_items = [0 => [], 3 => []];

        foreach ($items as $item) {
            if (!$this->isRelevantKey($item['key_'])) {
                continue;
            }

            $hostid = (string) $item['hostid'];
            $item['itemid'] = (string) $item['itemid'];
            $item['lastclock'] = (int) $item['lastclock'];
            $item['value_type'] = (int) $item['value_type'];
            $item['state'] = (int) $item['state'];

            $by_host[$hostid][] = $item;

            if ($this->needsHistory($item) && array_key_exists($item['value_type'], $history_items)) {
                $history_items[$item['value_type']][] = $item['itemid'];
            }
        }

        $history_hours = max(1, min(168, (int) $settings['history_hours']));
        $this->history = $this->getHistory($history_items, $history_hours);

        $problems = $this->getProblems(array_keys($hosts));
        $result = [];

        foreach ($hosts as $hostid => $host) {
            $hostid = (string) $hostid;
            $result[] = [
                'hostid'          => $hostid,
                'name'            => $host['name'],
                'technical_name'  => $host['host'],
                'enabled'         => (int) $host['status'] === 0,
                'maintenance'     => (int) $host['maintenance_status'] === 1,
                'interfaces_meta' => $host['interfaces'],
                'items'           => $by_host[$hostid] ?? [],
                'problems'        => $problems[$hostid] ?? []
            ];
        }

        usort($result, static fn(array $a, array $b): int => strcasecmp($a['name'], $b['name']));
        return $result;
    }

    private function isRelevantKey(string $key): bool {
        $exact_keys = [
            'rlCpuUtilDuringLastMinute.0',
            'sysUpTimeInstance',
            'icmpping',
            'zabbix[host,snmp,available]'
        ];

        if (in_array($key, $exact_keys, true)) {
            return true;
        }

        $prefixes = [
            'ifOperStatus.',
            'ifHCInOctets.',
            'ifHCOutOctets.',
            'ifInOctects.',
            'ifInOctets.',
            'ifOutOctets.',
            'system.cpu.util',
            'system.uptime',
            'net.if.'
        ];

        foreach ($prefixes as $prefix) {
            if (strncmp($key, $prefix, strlen($prefix)) === 0) {
                return true;
            }
        }

        return false;
    }

    private function needsHistory(array $item): bool {
        $key = $item['key_'];

        if ($key === 'rlCpuUtilDuringLastMinute.0' || str_starts_with($key, 'system.cpu.util')) {
            return true;
        }

        return str_starts_with($key, 'ifHCInOctets.')
            || str_starts_with($key, 'ifHCOutOctets.')
            || str_starts_with($key, 'ifInOctects.')
            || str_starts_with($key, 'ifInOctets.')
            || str_starts_with($key, 'ifOutOctets.')
            || strncmp($key, 'net.if.in[', 10) === 0
            || strncmp($key, 'net.if.out[', 11) === 0;
    }

    private function getHistory(array $itemids_by_type, int $hours): array {
        $result = [];
        $time_to = time();
        $time_from = $time_to - $hours * 3600;
        $recent_from = max($time_from, $time_to - 3600);
        $all_itemids = [];

        foreach ($itemids_by_type as $history_type => $itemids) {
            $itemids = array_values(array_unique($itemids));
            if (!$itemids) {
                continue;
            }
            $all_itemids = array_merge($all_itemids, $itemids);
            $this->appendRawHistory($result, (int) $history_type, $itemids, $recent_from, $time_to, 1);
        }

        if ($hours > 1 && $all_itemids) {
            try {
                $rows = API::Trend()->get([
                    'output'     => ['itemid', 'clock', 'value_min', 'value_avg', 'value_max'],
                    'itemids'    => array_values(array_unique($all_itemids)),
                    'time_from'  => $time_from,
                    'time_till'  => $recent_from - 1,
                    'sortfield'  => 'clock',
                    'sortorder'  => 'ASC',
                    'limit'      => max(5000, count($all_itemids) * ($hours + 2))
                ]);

                foreach ($rows as $row) {
                    $itemid = (string) $row['itemid'];
                    $result[$itemid][] = [
                        (int) $row['clock'] + 1800,
                        (float) $row['value_avg'],
                        (float) $row['value_min'],
                        (float) $row['value_max']
                    ];
                }
            } catch (\Throwable $e) {}
        }

        foreach ($result as $itemid => $points) {
            usort($points, static fn(array $a, array $b): int => $a[0] <=> $b[0]);
            $result[$itemid] = $this->downsample($points, 300);
        }

        return $result;
    }

    private function appendRawHistory(array &$result, int $type, array $itemids, int $from, int $till, int $hours): void {
        if ($till < $from) return;

        foreach (array_chunk($itemids, 10) as $chunk) {
            $rows = API::History()->get([
                'output'    => ['itemid', 'clock', 'value'],
                'history'   => $type,
                'itemids'   => $chunk,
                'time_from' => $from,
                'time_till' => $till,
                'sortfield' => 'clock',
                'sortorder' => 'DESC',
                'limit'     => 10000
            ]);

            foreach ($rows as $row) {
                $result[(string) $row['itemid']][] = [(int) $row['clock'], (float) $row['value']];
            }
        }
    }

    private function downsample(array $points, int $max): array {
        $cnt = count($points);
        if ($cnt <= $max) return $points;

        $span = max(1, (int) $points[$cnt - 1][0] - (int) $points[0][0]);
        $buckets = [];

        foreach ($points as $pt) {
            $idx = min($max - 1, (int) floor(((int) $pt[0] - (int) $points[0][0]) / $span * $max));
            $val = (float) $pt[1];

            if (!isset($buckets[$idx])) {
                $buckets[$idx] = ['clock' => (int) $pt[0], 'sum' => 0.0, 'count' => 0];
            }
            $buckets[$idx]['sum'] += $val;
            $buckets[$idx]['count']++;
        }

        return array_map(static fn($b) => [$b['clock'], $b['sum'] / $b['count']], array_values($buckets));
    }

    private function getProblems(array $hostids): array {
        $result = [];
        $rows = API::Trigger()->get([
            'output'            => ['triggerid', 'description', 'priority', 'lastchange'],
            'hostids'           => $hostids,
            'monitored'         => true,
            'filter'            => ['value' => 1],
            'expandDescription' => true,
            'sortfield'         => ['priority', 'lastchange'],
            'sortorder'         => 'DESC',
            'limit'             => 50,
            'selectHosts'       => ['hostid']
        ]);

        foreach ($rows as $problem) {
            foreach ($problem['hosts'] ?? [] as $host) {
                $result[(string) $host['hostid']][] = [
                    'eventid'  => (string) $problem['triggerid'],
                    'name'     => $problem['description'],
                    'severity' => (int) $problem['priority'],
                    'clock'    => (int) $problem['lastchange']
                ];
            }
        }

        return $result;
    }
}
EOF

# -------------------------------------------------------------
# 5. views/widget.edit.php
# -------------------------------------------------------------
cat << 'EOF' > "$MODULE_DIR/views/widget.edit.php"
<?php
declare(strict_types = 1);

/** @var CView $this */
/** @var array $data */

$form = new CWidgetFormView($data);

$form
    ->addField(new CWidgetFieldMultiSelectHostView($data['fields']['hostids']))
    ->addField(new CWidgetFieldTextBoxView($data['fields']['uplink_regex']))
    ->addField(new CWidgetFieldNumericBoxView($data['fields']['history_hours']))
    ->addField(new CWidgetFieldCheckBoxView($data['fields']['enable_auto_rotation']))
    ->addField(new CWidgetFieldNumericBoxView($data['fields']['page_display_period']))
    ->addFieldset(
        (new CWidgetFormFieldsetCollapsibleView(_('Secciones Visibles')))
            ->addField(new CWidgetFieldCheckBoxView($data['fields']['show_overview']))
            ->addField(new CWidgetFieldCheckBoxView($data['fields']['show_faceplate']))
            ->addField(new CWidgetFieldCheckBoxView($data['fields']['show_interfaces_table']))
    )
    ->addFieldset(
        (new CWidgetFormFieldsetCollapsibleView(_('Umbrales de Alerta')))
            ->addField(new CWidgetFieldNumericBoxView($data['fields']['cpu_warn']))
            ->addField(new CWidgetFieldNumericBoxView($data['fields']['cpu_crit']))
            ->addField(new CWidgetFieldNumericBoxView($data['fields']['bandwidth_warn']))
            ->addField(new CWidgetFieldNumericBoxView($data['fields']['bandwidth_crit']))
    )
    ->show();
EOF

# -------------------------------------------------------------
# 6. views/widget.view.php
# -------------------------------------------------------------
cat << 'EOF' > "$MODULE_DIR/views/widget.view.php"
<?php
declare(strict_types = 1);

/** @var CView $this */
/** @var array $data */

$payload = base64_encode(json_encode($data['payload'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE));

$root = (new CDiv())
    ->addClass('cisco-switch-root')
    ->setAttribute('data-payload', $payload);

(new CWidgetView($data))
    ->addItem($root)
    ->show();
EOF

# -------------------------------------------------------------
# 7. assets/css/widget.css
# -------------------------------------------------------------
cat << 'EOF' > "$MODULE_DIR/assets/css/widget.css"
div.dashboard-widget-cisco_sg_overview {
    padding: 0;
    overflow: hidden;
    --cs-bg: #10151d;
    --cs-chassis: #1e2630;
    --cs-panel: #26313f;
    --cs-panel-soft: #2f3c4c;
    --cs-text: #f0f4f8;
    --cs-muted: #8c9ba8;
    --cs-border: #3b4b5e;
    --cs-blue: #049fd9;
    --cs-green: #2ecc71;
    --cs-amber: #f39c12;
    --cs-red: #e74c3c;
}

.cisco-switch-root, .cisco-switch-root * {
    box-sizing: border-box;
}

.cisco-switch-root {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
    background: var(--cs-bg);
    color: var(--cs-text);
    font-family: system-ui, -apple-system, sans-serif;
    font-size: 11px;
}

.cs-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 14px;
    background: var(--cs-chassis);
    border-bottom: 1px solid var(--cs-border);
}

.cs-header-info h2 {
    margin: 0;
    font-size: 15px;
    font-weight: 700;
    color: var(--cs-text);
}

.cs-header-info p {
    margin: 2px 0 0;
    color: var(--cs-muted);
    font-size: 10px;
}

.cs-kpis {
    display: flex;
    gap: 8px;
}

.cs-kpi {
    padding: 6px 12px;
    background: var(--cs-panel);
    border: 1px solid var(--cs-border);
    border-radius: 6px;
    text-align: center;
}

.cs-kpi span {
    display: block;
    color: var(--cs-muted);
    font-size: 9px;
}

.cs-kpi strong {
    font-size: 13px;
    font-weight: 700;
    color: var(--cs-blue);
}

.cs-faceplate-container {
    padding: 14px;
    overflow-x: auto;
}

.cs-faceplate {
    display: inline-flex;
    align-items: center;
    gap: 16px;
    padding: 12px 16px;
    background: linear-gradient(180deg, #1b222b 0%, #11171f 100%);
    border: 2px solid #364455;
    border-radius: 8px;
    box-shadow: inset 0 1px 3px rgba(0,0,0,0.8), 0 4px 14px rgba(0,0,0,0.5);
}

.cs-brand {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding-right: 12px;
    border-right: 1px solid #364455;
}

.cs-brand strong {
    font-size: 14px;
    letter-spacing: 1px;
    color: var(--cs-blue);
}

.cs-brand small {
    font-size: 8px;
    color: var(--cs-muted);
}

.cs-matrix-24 {
    display: grid;
    grid-template-columns: repeat(12, 38px);
    grid-template-rows: repeat(2, 38px);
    gap: 6px;
}

.cs-uplink-block {
    display: grid;
    grid-template-rows: repeat(2, 38px);
    gap: 6px;
    padding-left: 12px;
    border-left: 1px dashed #364455;
}

.cs-port {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: space-between;
    padding: 3px;
    background: #0d1217;
    border: 1px solid #334050;
    border-radius: 4px;
    cursor: pointer;
    transition: transform 0.15s ease, border-color 0.15s ease;
}

.cs-port:hover {
    transform: scale(1.15);
    z-index: 10;
    border-color: var(--cs-blue);
    box-shadow: 0 4px 10px rgba(0,0,0,0.6);
}

.cs-port.is-sfp {
    background: #141c24;
    border-style: dashed;
}

.cs-port-num {
    font-size: 8px;
    font-weight: 700;
    color: var(--cs-muted);
    line-height: 1;
}

.cs-led {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #444;
}

.cs-port.up .cs-led {
    background: var(--cs-green);
    box-shadow: 0 0 6px var(--cs-green);
}

.cs-port.down .cs-led {
    background: #555;
}

.cs-port.has-traffic .cs-led {
    animation: cs-blink 0.8s infinite alternate;
}

@keyframes cs-blink {
    from { opacity: 1; }
    to { opacity: 0.35; }
}

.cs-jack {
    width: 18px;
    height: 12px;
    border: 1px solid #3b4a5b;
    border-top: 0;
    border-radius: 0 0 3px 3px;
    background: #161e27;
}

.cs-table-wrap {
    flex: 1;
    overflow: auto;
    padding: 10px 14px;
}

.cs-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 10px;
}

.cs-table th {
    padding: 6px 8px;
    text-align: left;
    background: var(--cs-panel);
    color: var(--cs-muted);
    border-bottom: 1px solid var(--cs-border);
}

.cs-table td {
    padding: 6px 8px;
    border-bottom: 1px solid var(--cs-border);
}

.cs-table tr:hover {
    background: var(--cs-panel-soft);
    cursor: pointer;
}

.cs-modal {
    position: fixed;
    inset: 0;
    z-index: 100000;
    display: grid;
    place-items: center;
    background: rgba(0,0,0,0.75);
    backdrop-filter: blur(3px);
}

.cs-modal-card {
    width: min(900px, 94vw);
    background: var(--cs-panel);
    border: 1px solid var(--cs-border);
    border-radius: 8px;
    padding: 16px;
    box-shadow: 0 16px 40px rgba(0,0,0,0.6);
}

.cs-modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 12px;
}

.cs-modal-header h3 {
    margin: 0;
    font-size: 14px;
}

.cs-modal-close {
    background: none;
    border: none;
    color: var(--cs-text);
    font-size: 18px;
    cursor: pointer;
}

canvas.cs-chart {
    width: 100%;
    height: 220px;
    background: #121820;
    border-radius: 6px;
}
EOF

# -------------------------------------------------------------
# 8. assets/js/class.widget.js (Con orden consecutivo 1-12 y 13-24)
# -------------------------------------------------------------
cat << 'EOF' > "$MODULE_DIR/assets/js/class.widget.js"
class WidgetCiscoSGOverview extends CWidget {

    onInitialize() {
        super.onInitialize();
        this._selected_hostid = null;
        this._payload = null;
        this._modal = null;
    }

    setContents(response) {
        super.setContents(response);
        this._renderWidget();
    }

    onResize() {
        super.onResize();
    }

    _renderWidget() {
        const root = this._body.querySelector('.cisco-switch-root');
        if (!root) return;

        try {
            this._payload = JSON.parse(decodeURIComponent(escape(atob(root.dataset.payload))));
        } catch (e) {
            root.innerHTML = '<div style="padding:20px;text-align:center;">Error al decodificar datos del switch.</div>';
            return;
        }

        const hosts = this._payload.hosts || [];
        if (!hosts.length) {
            root.innerHTML = '<div style="padding:20px;text-align:center;">Selecciona al menos un switch Cisco en la configuración.</div>';
            return;
        }

        if (!hosts.some(h => h.hostid === this._selected_hostid)) {
            this._selected_hostid = hosts[0].hostid;
        }

        const currentHost = hosts.find(h => h.hostid === this._selected_hostid);
        const switchData = this._parseSwitchData(currentHost);

        root.innerHTML = `
            <header class="cs-header">
                <div class="cs-header-info">
                    <h2>${this._escape(currentHost.name)}</h2>
                    <p>Uptime: ${switchData.uptime} | IP: ${switchData.ip} | Puertos UP: ${switchData.upCount} / ${switchData.ports.length}</p>
                </div>
                <div class="cs-kpis">
                    <div class="cs-kpi"><span>CPU (1 min)</span><strong>${switchData.cpu !== null ? switchData.cpu + '%' : 'N/D'}</strong></div>
                    <div class="cs-kpi"><span>Tráfico Total IN</span><strong>${this._formatBits(switchData.totalIn)}</strong></div>
                    <div class="cs-kpi"><span>Tráfico Total OUT</span><strong>${this._formatBits(switchData.totalOut)}</strong></div>
                </div>
            </header>
            
            <div class="cs-faceplate-container">
                <div class="cs-faceplate">
                    <div class="cs-brand">
                        <strong>CISCO</strong>
                        <small>SG200-26P</small>
                    </div>
                    <!-- Fila 1: 1 a 12 | Fila 2: 13 a 24 -->
                    <div class="cs-matrix-24">
                        ${this._render24PortMatrix(switchData.ports)}
                    </div>
                    <!-- Bloque Uplink / SFP: 25 y 26 -->
                    <div class="cs-uplink-block">
                        ${this._renderSfpBlock(switchData.ports)}
                    </div>
                </div>
            </div>

            <div class="cs-table-wrap">
                <table class="cs-table">
                    <thead>
                        <tr>
                            <th>Puerto</th>
                            <th>Estado</th>
                            <th>Tráfico Entrada</th>
                            <th>Tráfico Salida</th>
                            <th>Acciones</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${switchData.ports.map(p => `
                            <tr data-port-id="${p.index}">
                                <td><strong>${this._escape(p.name)}</strong></td>
                                <td><span style="color:${p.status === 1 ? 'var(--cs-green)' : 'var(--cs-muted)'};font-weight:700;">${p.status === 1 ? 'UP' : 'DOWN'}</span></td>
                                <td>${this._formatBits(p.inTraffic)}</td>
                                <td>${this._formatBits(p.outTraffic)}</td>
                                <td><button style="background:var(--cs-panel);border:1px solid var(--cs-border);color:var(--cs-text);padding:2px 6px;border-radius:4px;cursor:pointer;">Histórico</button></td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>
            </div>
        `;

        root.querySelectorAll('[data-chart-in]').forEach(el => {
            el.addEventListener('click', () => {
                this._openChartModal(
                    el.dataset.portName,
                    el.dataset.chartIn,
                    el.dataset.chartOut
                );
            });
        });

        root.querySelectorAll('.cs-table tbody tr').forEach(row => {
            row.addEventListener('click', () => {
                const p = switchData.ports.find(x => x.index == row.dataset.portId);
                if (p) this._openChartModal(p.name, p.inItemId, p.outItemId);
            });
        });
    }

    _parseSwitchData(host) {
        const items = host.items || [];
        let cpu = null;
        let uptimeSec = null;
        let totalIn = 0;
        let totalOut = 0;
        let upCount = 0;

        const portsMap = {};

        items.forEach(item => {
            const key = item.key_;

            if (key === 'rlCpuUtilDuringLastMinute.0' || key.startsWith('system.cpu.util')) {
                cpu = item.lastvalue !== '' ? Math.round(Number(item.lastvalue)) : null;
            }
            if (key === 'sysUpTimeInstance' || key.startsWith('system.uptime')) {
                uptimeSec = item.lastvalue !== '' ? Math.floor(Number(item.lastvalue) / 100) : null;
            }

            const matchIndex = key.match(/\.(\d+)$/);
            if (matchIndex) {
                const idx = parseInt(matchIndex[1], 10);
                if (!portsMap[idx]) {
                    const portNumber = idx >= 49 && idx <= 74 ? idx - 48 : idx;
                    portsMap[idx] = {
                        index: idx,
                        portNumber: portNumber,
                        name: `GE${portNumber < 10 ? '0' + portNumber : portNumber}`,
                        status: 2,
                        inTraffic: 0,
                        outTraffic: 0,
                        inItemId: null,
                        outItemId: null,
                        isSfp: portNumber >= 25
                    };
                }

                if (key.startsWith('ifOperStatus.')) {
                    portsMap[idx].status = Number(item.lastvalue) || 2;
                } else if (key.startsWith('ifHCInOctets.') || key.startsWith('ifInOctects.') || key.startsWith('ifInOctets.')) {
                    portsMap[idx].inTraffic = Number(item.lastvalue) || 0;
                    portsMap[idx].inItemId = item.itemid;
                } else if (key.startsWith('ifHCOutOctets.') || key.startsWith('ifOutOctets.')) {
                    portsMap[idx].outTraffic = Number(item.lastvalue) || 0;
                    portsMap[idx].outItemId = item.itemid;
                }
            }
        });

        const ports = Object.values(portsMap).sort((a, b) => a.portNumber - b.portNumber);

        ports.forEach(p => {
            if (p.status === 1) upCount++;
            totalIn += p.inTraffic;
            totalOut += p.outTraffic;
        });

        const mainIf = (host.interfaces_meta || []).find(i => String(i.main) === '1') || (host.interfaces_meta || [])[0];

        return {
            cpu,
            uptime: this._formatUptime(uptimeSec),
            ip: mainIf ? (mainIf.ip || mainIf.dns) : 'N/D',
            upCount,
            totalIn,
            totalOut,
            ports
        };
    }

    _render24PortMatrix(ports) {
        let html = '';

        // Fila 1 (arriba): Puertos 1 al 12 consecutivos
        for (let i = 1; i <= 12; i++) {
            const p = ports.find(port => port.portNumber === i);
            html += this._renderPortHtml(p);
        }

        // Fila 2 (abajo): Puertos 13 al 24 consecutivos
        for (let i = 13; i <= 24; i++) {
            const p = ports.find(port => port.portNumber === i);
            html += this._renderPortHtml(p);
        }

        return html;
    }

    _renderSfpBlock(ports) {
        let html = '';
        [25, 26].forEach(num => {
            const p = ports.find(port => port.portNumber === num);
            html += this._renderPortHtml(p);
        });
        return html;
    }

    _renderPortHtml(p) {
        if (!p) return '<div class="cs-port" style="visibility:hidden;"></div>';
        const hasTraffic = (p.inTraffic + p.outTraffic) > 50000;
        return `
            <div class="cs-port ${p.status === 1 ? 'up' : 'down'} ${hasTraffic ? 'has-traffic' : ''} ${p.isSfp ? 'is-sfp' : ''}"
                 data-chart-in="${p.inItemId || ''}"
                 data-chart-out="${p.outItemId || ''}"
                 data-port-name="${this._escape(p.name)}"
                 title="${p.name} | ${p.status === 1 ? 'UP' : 'DOWN'}&#10;IN: ${this._formatBits(p.inTraffic)}&#10;OUT: ${this._formatBits(p.outTraffic)}">
                <span class="cs-port-num">${p.portNumber}</span>
                <span class="cs-led"></span>
                <div class="cs-jack"></div>
            </div>
        `;
    }

    _openChartModal(title, inItemId, outItemId) {
        this._closeModal();

        this._modal = document.createElement('div');
        this._modal.className = 'cs-modal';
        this._modal.innerHTML = `
            <div class="cs-modal-card">
                <div class="cs-modal-header">
                    <h3>Tráfico Histórico: ${this._escape(title)}</h3>
                    <button class="cs-modal-close">&times;</button>
                </div>
                <canvas class="cs-chart"></canvas>
                <div style="display:flex;justify-content:space-between;margin-top:8px;font-size:10px;color:var(--cs-muted);">
                    <span><i style="display:inline-block;width:8px;height:8px;background:#049fd9;border-radius:50%;margin-right:4px;"></i>Entrada (IN)</span>
                    <span><i style="display:inline-block;width:8px;height:8px;background:#2ecc71;border-radius:50%;margin-right:4px;"></i>Salida (OUT)</span>
                </div>
            </div>
        `;

        document.body.appendChild(this._modal);
        this._modal.querySelector('.cs-modal-close').addEventListener('click', () => this._closeModal());
        this._modal.addEventListener('click', (e) => { if (e.target === this._modal) this._closeModal(); });

        const canvas = this._modal.querySelector('canvas.cs-chart');
        this._drawModalChart(canvas, [inItemId, outItemId].filter(Boolean));
    }

    _drawModalChart(canvas, itemids) {
        const ctx = canvas.getContext('2d');
        const rect = canvas.getBoundingClientRect();
        canvas.width = rect.width;
        canvas.height = rect.height;

        const colors = ['#049fd9', '#2ecc71'];
        const series = itemids.map((id, idx) => ({
            points: (this._payload.history[id] || []),
            color: colors[idx % colors.length]
        })).filter(s => s.points.length > 0);

        if (!series.length) {
            ctx.fillStyle = '#8c9ba8';
            ctx.fillText('Sin datos históricos recientes en Zabbix para este puerto.', 20, canvas.height / 2);
            return;
        }

        const allVals = series.flatMap(s => s.points.map(p => p[1]));
        const maxVal = Math.max(1000, ...allVals) * 1.1;
        const pad = { t: 20, b: 25, l: 50, r: 20 };
        const w = canvas.width - pad.l - pad.r;
        const h = canvas.height - pad.t - pad.b;

        ctx.strokeStyle = 'rgba(255,255,255,0.1)';
        ctx.beginPath();
        ctx.moveTo(pad.l, pad.t); ctx.lineTo(pad.l, pad.t + h); ctx.lineTo(pad.l + w, pad.t + h);
        ctx.stroke();

        series.forEach(s => {
            const pts = s.points;
            const minT = pts[0][0];
            const maxT = pts[pts.length - 1][0];
            const timeSpan = Math.max(1, maxT - minT);

            ctx.beginPath();
            ctx.strokeStyle = s.color;
            ctx.lineWidth = 2;

            pts.forEach((pt, i) => {
                const x = pad.l + ((pt[0] - minT) / timeSpan) * w;
                const y = pad.t + h - (pt[1] / maxVal) * h;
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            });
            ctx.stroke();
        });
    }

    _closeModal() {
        if (this._modal) {
            this._modal.remove();
            this._modal = null;
        }
    }

    _formatBits(val) {
        if (!val || isNaN(val)) return '0 bps';
        const units = ['bps', 'Kbps', 'Mbps', 'Gbps'];
        let i = 0;
        let v = Number(val);
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i++;
        }
        return `${v.toFixed(1)} ${units[i]}`;
    }

    _formatUptime(sec) {
        if (!sec || isNaN(sec)) return 'N/D';
        const d = Math.floor(sec / 86400);
        const h = Math.floor((sec % 86400) / 3600);
        const m = Math.floor((sec % 3600) / 60);
        return `${d}d ${h}h ${m}m`;
    }

    _escape(str) {
        return String(str || '').replace(/[&<>'"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[c]));
    }
}
EOF

# -------------------------------------------------------------
# 9. README.md
# -------------------------------------------------------------
cat << 'EOF' > "$MODULE_DIR/README.md"
# Cisco SG Overview

Widget para Zabbix 7.0 / 7.4 orientado a conmutadores Cisco Small Business (SG200-26P y compatibles).

**Autor:** YoelYoestar  
**Versión:** 1.0.0  
**Compatibilidad:** Zabbix 7.0 LTS / 7.4 (Manifest v2.0)

## Funciones
- Frontal físico con 24 puertos Ethernet en disposición consecutiva (1-12 fila superior, 13-24 fila inferior) y bloque Uplink SFP (puertos 25 y 26).
- LEDs de enlace y actividad con animación de parpadeo ante tráfico.
- Tarjetas de CPU (1 min), tiempo encendido (uptime) y tráfico total acumulado.
- Modal Canvas para análisis histórico de ancho de banda por interfaz.
- Compatibilidad directa con plantillas SNMP fijas (Cisco_SG200-26P).
EOF

# -------------------------------------------------------------
# 10. Asignación de permisos y validación de sintaxis
# -------------------------------------------------------------
echo "==> Configurando permisos para el usuario zabbix..."
chown -R zabbix:zabbix "$MODULE_DIR"
chmod -R 755 "$MODULE_DIR"

echo "==> Validando sintaxis PHP..."
find "$MODULE_DIR" -name "*.php" -exec php -l {} \;

# -------------------------------------------------------------
# 11. Sincronización Git automática (si existe repositorio)
# -------------------------------------------------------------
if [ -d "$MODULE_DIR/.git" ]; then
    echo "==> Repositorio Git detectado en $MODULE_DIR. Sincronizando..."
    cd "$MODULE_DIR"
    git add .
    git commit -m "feat(widget): complete Cisco SG200 overview widget deployment with sequential port order (1-12 top, 13-24 bottom)" || true
    CURRENT_BRANCH=$(git branch --show-current || echo "main")
    echo "==> Subiendo a GitHub en la rama $CURRENT_BRANCH..."
    git push origin "$CURRENT_BRANCH" || echo "Nota: Para completar el push introduce tus credenciales o token de GitHub."
fi

echo ""
echo "=========================================================="
echo "==> ¡Despliegue finalizado con éxito!"
echo "==> 1. En Zabbix: Administración -> General -> Módulos"
echo "==> 2. Haz clic en 'Escanear directorio'"
echo "==> 3. Habilita 'Cisco SG Overview'"
echo "==> 4. Haz Ctrl+F5 en tu navegador para recargar la caché"
echo "=========================================================="