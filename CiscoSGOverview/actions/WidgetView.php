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
        foreach (self::DEFAULTS as $key =>$default) {
            $value =$settings[$key] ?? $default;
            $result[$key] = is_int($default) ? (int) $value : (string)$value;
        }
        return $result;
    }

    private function getHostsData(array $hostids, array $settings): array {$hosts = API::Host()->get([
            'output'           => ['hostid', 'host', 'name', 'status', 'maintenance_status'],
            'hostids'          => $hostids,
            'selectInterfaces' => ['interfaceid', 'ip', 'dns', 'type', 'main', 'available'],
            'preservekeys'     => true
        ]);

        if (!$hosts) {$this->history = [];
            return [];
        }

        $items = API::Item()->get([
            'output'    => ['itemid', 'hostid', 'name', 'key_', 'lastvalue', 'lastclock', 'units', 'value_type', 'state'],
            'hostids'   => array_keys($hosts),
            'filter'    => ['status' => 0],
            'webitems'  => true
        ]);

        $by_host = [];$history_items = [0 => [], 3 => []];

        foreach ($items as$item) {
            if (!$this->isRelevantKey($item['key_'])) {
                continue;
            }

            $hostid = (string)$item['hostid'];
            $item['itemid'] = (string)$item['itemid'];
            $item['lastclock'] = (int)$item['lastclock'];
            $item['value_type'] = (int)$item['value_type'];
            $item['state'] = (int)$item['state'];

            $by_host[$hostid][] =$item;

            if ($this->needsHistory($item) && array_key_exists($item['value_type'], $history_items)) {$history_items[$item['value_type']][] =$item['itemid'];
            }
        }

        $history_hours = max(1, min(168, (int)$settings['history_hours']));
        $this->history =$this->getHistory($history_items,$history_hours);

        $problems =$this->getProblems(array_keys($hosts));$result = [];

        foreach ($hosts as $hostid =>$host) {
            $hostid = (string)$hostid;
            $result[] = [
                'hostid'          => $hostid,
                'name'            => $host['name'],
                'technical_name'  => $host['host'],
                'enabled'         => (int) $host['status'] === 0,
                'maintenance'     => (int) $host['maintenance_status'] === 1,
                'interfaces_meta' =>$host['interfaces'],
                'items'           => $by_host[$hostid] ?? [],
                'problems'        => $problems[$hostid] ?? []
            ];
        }

        usort($result, static fn(array $a, array$b): int => strcasecmp($a['name'],$b['name']));
        return $result;
    }

    private function isRelevantKey(string $key): bool {$exact_keys = [
            'rlCpuUtilDuringLastMinute.0',
            'sysUpTimeInstance',
            'icmpping',
            'zabbix[host,snmp,available]'
        ];

        if (in_array($key,$exact_keys, true)) {
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

        foreach ($prefixes as$prefix) {
            if (strncmp($key, $prefix, strlen($prefix)) === 0) {
                return true;
            }
        }

        return false;
    }

    private function needsHistory(array $item): bool {
        $key =$item['key_'];

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

    private function getHistory(array $itemids_by_type, int $hours): array {$result = [];
        $time_to = time();$time_from = $time_to -$hours * 3600;
        $recent_from = max($time_from, $time_to - 3600);$all_itemids = [];

        foreach ($itemids_by_type as $history_type =>$itemids) {
            $itemids = array_values(array_unique($itemids));
            if (!$itemids) {
                continue;
            }$all_itemids = array_merge($all_itemids,$itemids);
            $this->appendRawHistory($result, (int) $history_type,$itemids, $recent_from,$time_to, 1);
        }

        if ($hours > 1 &&$all_itemids) {
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

                foreach ($rows as$row) {
                    $itemid = (string)$row['itemid'];
                    $result[$itemid][] = [
                        (int) $row['clock'] + 1800,
                        (float)$row['value_avg'],
                        (float) $row['value_min'],
                        (float) $row['value_max']
                    ];
                }
            } catch (\Throwable $e) {}
        }

        foreach ($result as $itemid =>$points) {
            usort($points, static fn(array $a, array$b): int => $a[0] <=>$b[0]);
            $result[$itemid] = $this->downsample($points, 300);
        }

        return $result;
    }

    private function appendRawHistory(array &$result, int$type, array $itemids, int$from, int $till, int$hours): void {
        if ($till <$from) return;

        foreach (array_chunk($itemids, 10) as $chunk) {$rows = API::History()->get([
                'output'    => ['itemid', 'clock', 'value'],
                'history'   => $type,
                'itemids'   => $chunk,
                'time_from' => $from,
                'time_till' => $till,
                'sortfield' => 'clock',
                'sortorder' => 'DESC',
                'limit'     => 10000
            ]);

            foreach ($rows as$row) {
                $result[(string)$row['itemid']][] = [(int) $row['clock'], (float)$row['value']];
            }
        }
    }

    private function downsample(array $points, int$max): array {
        $cnt = count($points);
        if ($cnt <= $max) return$points;

        $span = max(1, (int) $points[$cnt - 1][0] - (int) $points[0][0]);$buckets = [];

        foreach ($points as$pt) {
            $idx = min($max - 1, (int) floor(((int) $pt[0] - (int)$points[0][0]) / $span * $max));
            $val = (float)$pt[1];

            if (!isset($buckets[$idx])) {
                $buckets[$idx] = ['clock' => (int) $pt[0], 'sum' => 0.0, 'count' => 0];
            }$buckets[$idx]['sum'] +=$val;
            $buckets[$idx]['count']++;
        }

        return array_map(static fn($b) => [$b['clock'],$b['sum'] / $b['count']], array_values($buckets));
    }

    private function getProblems(array $hostids): array {
        $result = [];$rows = API::Trigger()->get([
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

        foreach ($rows as$problem) {
            foreach ($problem['hosts'] ?? [] as$host) {
                $result[(string)$host['hostid']][] = [
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
