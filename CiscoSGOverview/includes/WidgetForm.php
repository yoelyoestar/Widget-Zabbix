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
                (new CWidgetFieldTextBox('uplink_regex', _('Expresión regular Uplinks')))
                    ->setDefault('(uplink|trunk|sfp|core|ge25|ge26)')
            )
            ->addField(
                (new CWidgetFieldNumericBox('history_hours', _('Histórico (horas)')))
                    ->setDefault(12)
            )
            ->addField(
                (new CWidgetFieldCheckBox('enable_auto_rotation', _('Rotación automática de switches')))
                    ->setDefault(0)
            )
            ->addField(
                (new CWidgetFieldNumericBox('page_display_period', _('Segundos por switch')))
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
