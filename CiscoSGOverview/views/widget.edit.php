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
