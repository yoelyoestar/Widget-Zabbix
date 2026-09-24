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
