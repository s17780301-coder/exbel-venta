import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formato.dart';
import '../../data/ajustes_repo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../tema/tema.dart';
import 'dialogos_venta.dart';

class ResultadoCobro {
  ResultadoCobro({required this.pago, required this.imprimir, this.cliente, this.notas = ''});
  final Pago pago;
  final bool imprimir;
  final Cliente? cliente;
  final String notas;
}

/// F12: cobrar. Efectivo, tarjeta, vales, dólares, crédito o mixto.
Future<ResultadoCobro?> cobrar(BuildContext context, int totalCentavos, {Cliente? cliente}) {
  return showDialog<ResultadoCobro>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _Cobro(totalCentavos, cliente),
  );
}

enum _Forma { efectivo, tarjeta, vales, dolares, credito, mixto }

const _nombres = {
  _Forma.efectivo: 'Efectivo',
  _Forma.tarjeta: 'Tarjeta',
  _Forma.vales: 'Vales',
  _Forma.dolares: 'Dólares',
  _Forma.credito: 'Crédito',
  _Forma.mixto: 'Mixto',
};

class _Cobro extends StatefulWidget {
  const _Cobro(this.total, this.cliente);
  final int total;
  final Cliente? cliente;

  @override
  State<_Cobro> createState() => _CobroState();
}

class _CobroState extends State<_Cobro> {
  _Forma _forma = _Forma.efectivo;
  late Cliente? _cliente = widget.cliente;
  final _pagoCon = TextEditingController();
  final _referencia = TextEditingController();
  final _dolares = TextEditingController();
  late final _tc = TextEditingController(text: (repos.ajustes.entero(Ajuste.tipoCambio) / 100).toStringAsFixed(2));
  final _notas = TextEditingController();
  // Mixto.
  final _mEf = TextEditingController();
  final _mTa = TextEditingController();
  final _mVa = TextEditingController();
  final _mUsd = TextEditingController();
  final _mCr = TextEditingController();
  final _foco = FocusNode();

  int get total => widget.total;

  @override
  void dispose() {
    for (final c in [_pagoCon, _referencia, _dolares, _tc, _notas, _mEf, _mTa, _mVa, _mUsd, _mCr]) {
      c.dispose();
    }
    _foco.dispose();
    super.dispose();
  }

  int _tipoCambio() => leerPesos(_tc.text) ?? repos.ajustes.entero(Ajuste.tipoCambio);
  int _usdAPesos(String t) => ((leerCantidad(t) ?? 0) * _tipoCambio()).round();

  /// (pago, mensaje de error)
  (Pago?, String?) _armarPago() {
    switch (_forma) {
      case _Forma.efectivo:
        final recibido = _pagoCon.text.trim().isEmpty ? total : leerPesos(_pagoCon.text);
        if (recibido == null) return (null, 'Escribe con cuánto paga.');
        if (recibido < total) {
          if (!repos.ajustes.si(Ajuste.permitirCobroMenor)) {
            return (null, 'Faltan ${formatoPesos(total - recibido)}. Usa "Mixto" o "Crédito" para el resto.');
          }
        }
        return (Pago(efectivoCentavos: total, recibidoCentavos: recibido), null);
      case _Forma.tarjeta:
        return (Pago(tarjetaCentavos: total, referencia: _referencia.text.trim()), null);
      case _Forma.vales:
        return (Pago(valesCentavos: total), null);
      case _Forma.dolares:
        final pesos = _usdAPesos(_dolares.text);
        if (pesos < total) return (null, 'Los dólares no alcanzan. Faltan ${formatoPesos(total - pesos)}.');
        // Los dólares entran a la caja; el cambio sale en pesos (efectivo negativo).
        return (
          Pago(dolaresCentavos: pesos, efectivoCentavos: total - pesos, referencia: 'USD ${_dolares.text} TC ${_tc.text}'),
          null
        );
      case _Forma.credito:
        if (_cliente == null) return (null, 'Elige el cliente al que se le fía.');
        return (Pago(creditoCentavos: total), null);
      case _Forma.mixto:
        final ef = leerPesos(_mEf.text) ?? 0;
        final ta = leerPesos(_mTa.text) ?? 0;
        final va = leerPesos(_mVa.text) ?? 0;
        final usd = _usdAPesos(_mUsd.text);
        final cr = leerPesos(_mCr.text) ?? 0;
        if (cr > 0 && _cliente == null) return (null, 'Para dejar una parte a crédito elige el cliente.');
        final otros = ta + va + usd + cr;
        if (otros > total) return (null, 'Tarjeta, vales, dólares y crédito suman más que el total.');
        final faltaEfectivo = total - otros;
        if (ef < faltaEfectivo) return (null, 'Faltan ${formatoPesos(faltaEfectivo - ef)}.');
        return (
          Pago(
            efectivoCentavos: faltaEfectivo,
            recibidoCentavos: ef,
            tarjetaCentavos: ta,
            valesCentavos: va,
            dolaresCentavos: usd,
            creditoCentavos: cr,
            referencia: _referencia.text.trim(),
          ),
          null
        );
    }
  }

  int _cambio() {
    switch (_forma) {
      case _Forma.efectivo:
        final r = leerPesos(_pagoCon.text) ?? total;
        return r - total;
      case _Forma.dolares:
        return _usdAPesos(_dolares.text) - total;
      case _Forma.mixto:
        final otros = (leerPesos(_mTa.text) ?? 0) + (leerPesos(_mVa.text) ?? 0) + _usdAPesos(_mUsd.text) + (leerPesos(_mCr.text) ?? 0);
        return (leerPesos(_mEf.text) ?? 0) - (total - otros);
      default:
        return 0;
    }
  }

  void _terminar(bool imprimir) {
    final (pago, error) = _armarPago();
    if (pago == null) return aviso(context, error!);
    if (pago.creditoCentavos > 0 && _cliente != null && _cliente!.tieneLimite &&
        _cliente!.saldoCentavos + pago.creditoCentavos > _cliente!.limiteCentavos) {
      return aviso(context, '${_cliente!.nombre} excede su límite de crédito. Disponible: ${formatoPesos(_cliente!.disponibleCentavos)}.');
    }
    final usd = _forma == _Forma.dolares ? _usdAPesos(_dolares.text) : 0;
    Navigator.pop(
      context,
      ResultadoCobro(
        pago: pago,
        imprimir: imprimir,
        cliente: _cliente,
        notas: [
          _notas.text.trim(),
          if (usd > total) 'Cambio en pesos: ${formatoPesos(usd - total)}',
        ].where((x) => x.isNotEmpty).join(' · '),
      ),
    );
  }

  Future<void> _elegirCliente() async {
    final c = await elegirCliente(context);
    if (c != null) setState(() => _cliente = c.id.isEmpty ? null : c);
  }

  @override
  Widget build(BuildContext context) {
    final cambio = _cambio();
    final formas = [
      _Forma.efectivo,
      _Forma.tarjeta,
      if (repos.ajustes.si(Ajuste.aceptarVales)) _Forma.vales,
      if (repos.ajustes.si(Ajuste.aceptarDolares)) _Forma.dolares,
      if (repos.ajustes.si(Ajuste.usarCredito)) _Forma.credito,
      _Forma.mixto,
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () => _terminar(true),
        const SingleActivator(LogicalKeyboardKey.f2): () => _terminar(false),
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
      },
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 760,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: ExColor.tinta,
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
              child: Row(children: [
                Text('Cobrar', style: ExTexto.titulo(26, color: ExColor.concreto)),
                const Spacer(),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Total a cobrar', style: TextStyle(color: ExColor.textoClaro2)),
                  Text(formatoPesos(total), style: ExTexto.titulo(48, color: ExColor.concreto)),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in formas)
                  ChoiceChip(
                    label: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(_nombres[f]!, style: const TextStyle(fontSize: 15)),
                    ),
                    selected: _forma == f,
                    onSelected: (_) => setState(() => _forma = f),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
              child: Focus(
                // Al teclear se recalcula el cambio.
                onKeyEvent: (_, __) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                  return KeyEventResult.ignored;
                },
                child: _campos(),
              ),
            ),
            if (cambio > 0 && (_forma == _Forma.efectivo || _forma == _Forma.dolares || _forma == _Forma.mixto))
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(color: ExColor.verdeSuave, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Text('Su cambio', style: TextStyle(fontSize: 18)),
                  const Spacer(),
                  Text(formatoPesos(cambio), style: ExTexto.titulo(36, color: ExColor.verde)),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
              child: TextField(
                controller: _notas,
                decoration: const InputDecoration(labelText: 'Nota en el ticket (opcional)'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Esc  Cancelar')),
                const Spacer(),
                OutlinedButton(onPressed: () => _terminar(false), child: const Text('F2  Solo cobrar')),
                const SizedBox(width: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: ExColor.acento,
                      foregroundColor: ExColor.tinta,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18)),
                  onPressed: () => _terminar(true),
                  child: const Text('F1  Cobrar e imprimir', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _panelCliente({bool obligatorio = false}) {
    final c = _cliente;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: obligatorio && c == null ? ExColor.acento : ExColor.linea),
      ),
      child: Row(children: [
        const Icon(Icons.person_outline),
        const SizedBox(width: 10),
        Expanded(
          child: c == null
              ? const Text('Sin cliente')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('Debe ${formatoPesos(c.saldoCentavos)}'
                      '${c.tieneLimite ? ' · Disponible ${formatoPesos(c.disponibleCentavos)}' : ' · Sin límite'}',
                      style: const TextStyle(color: ExColor.texto2)),
                ]),
        ),
        OutlinedButton(onPressed: _elegirCliente, child: Text(c == null ? 'Elegir cliente' : 'Cambiar')),
      ]),
    );
  }

  Widget _campos() {
    void recalcular(String _) => setState(() {});
    switch (_forma) {
      case _Forma.efectivo:
        return CampoNumero(
          controller: _pagoCon,
          etiqueta: 'Pagó con (\$)',
          ayuda: 'Vacío = pago exacto. ENTER cobra e imprime.',
          autofocus: true,
          onChanged: recalcular,
          onSubmitted: (_) => _terminar(true),
        );
      case _Forma.tarjeta:
        return TextField(
          controller: _referencia,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Referencia / autorización (opcional)'),
          onSubmitted: (_) => _terminar(true),
        );
      case _Forma.vales:
        return const Text('Se cobra el total con vales de despensa. Los vales no dan cambio.');
      case _Forma.dolares:
        return Row(children: [
          Expanded(
              child: CampoNumero(
                  controller: _dolares,
                  etiqueta: 'Dólares recibidos (USD)',
                  autofocus: true,
                  onChanged: recalcular,
                  onSubmitted: (_) => _terminar(true))),
          const SizedBox(width: 12),
          Expanded(child: CampoNumero(controller: _tc, etiqueta: 'Tipo de cambio (\$ por dólar)', onChanged: recalcular)),
          const SizedBox(width: 12),
          Text('Total en USD: ${(total / _tipoCambio()).toStringAsFixed(2)}'),
        ]);
      case _Forma.credito:
        return _panelCliente(obligatorio: true);
      case _Forma.mixto:
        return Column(children: [
          Row(children: [
            Expanded(child: CampoNumero(controller: _mEf, etiqueta: 'Efectivo recibido', autofocus: true, onChanged: recalcular)),
            const SizedBox(width: 12),
            Expanded(child: CampoNumero(controller: _mTa, etiqueta: 'Tarjeta', onChanged: recalcular)),
            const SizedBox(width: 12),
            Expanded(child: CampoNumero(controller: _mVa, etiqueta: 'Vales', onChanged: recalcular)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: CampoNumero(controller: _mUsd, etiqueta: 'Dólares (USD)', onChanged: recalcular)),
            const SizedBox(width: 12),
            Expanded(child: CampoNumero(controller: _mCr, etiqueta: 'A crédito', onChanged: recalcular)),
            const SizedBox(width: 12),
            Expanded(
                child: TextField(controller: _referencia, decoration: const InputDecoration(labelText: 'Ref. tarjeta'))),
          ]),
          const SizedBox(height: 12),
          if ((leerPesos(_mCr.text) ?? 0) > 0) _panelCliente(obligatorio: true),
        ]);
    }
  }
}
