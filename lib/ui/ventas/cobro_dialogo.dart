import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formato.dart';
import '../../data/ajustes_repo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../tema/tema.dart';
import '../zoom.dart';
import 'dialogos_venta.dart';

class ResultadoCobro {
  ResultadoCobro({required this.pago, required this.imprimir, this.cliente, this.notas = ''});
  final Pago pago;
  final bool imprimir;
  final Cliente? cliente;
  final String notas;
}

/// F12: cobrar: total grande, forma de pago con íconos,
/// "Pagó con" y "Su cambio", y a la derecha F1 / F2 / ESC / F4.
/// En "Mixto" se combinan efectivo, tarjeta, transferencia, vales, dólares
/// y crédito.
Future<ResultadoCobro?> cobrar(BuildContext context, int totalCentavos, {Cliente? cliente, double articulos = 0}) {
  return showDialog<ResultadoCobro>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _Cobro(totalCentavos, cliente, articulos),
  );
}

enum _Forma { efectivo, tarjeta, transferencia, credito, vales, dolares, mixto }

const _nombres = {
  _Forma.efectivo: 'Efectivo',
  _Forma.tarjeta: 'Tarjeta',
  _Forma.transferencia: 'Transferencia',
  _Forma.credito: 'Crédito',
  _Forma.vales: 'Vales',
  _Forma.dolares: 'Dólares',
  _Forma.mixto: 'Mixto',
};

const _iconos = {
  _Forma.efectivo: Icons.payments_outlined,
  _Forma.tarjeta: Icons.credit_card,
  _Forma.transferencia: Icons.account_balance_outlined,
  _Forma.credito: Icons.person_outline,
  _Forma.vales: Icons.confirmation_number_outlined,
  _Forma.dolares: Icons.attach_money,
  _Forma.mixto: Icons.call_split,
};

class _Cobro extends StatefulWidget {
  const _Cobro(this.total, this.cliente, this.articulos);
  final int total;
  final Cliente? cliente;
  final double articulos;

  @override
  State<_Cobro> createState() => _CobroState();
}

class _CobroState extends State<_Cobro> {
  _Forma _forma = _Forma.efectivo;
  late Cliente? _cliente = widget.cliente;
  late final _pagoCon = TextEditingController(text: (widget.total / 100).toStringAsFixed(2))
    ..selection = TextSelection(baseOffset: 0, extentOffset: (widget.total / 100).toStringAsFixed(2).length);
  final _referencia = TextEditingController();
  final _dolares = TextEditingController();
  late final _tc = TextEditingController(text: (repos.ajustes.entero(Ajuste.tipoCambio) / 100).toStringAsFixed(2));
  String _notas = '';
  // Mixto.
  final _mEf = TextEditingController();
  final _mTa = TextEditingController();
  final _mTr = TextEditingController();
  final _mVa = TextEditingController();
  final _mUsd = TextEditingController();
  final _mCr = TextEditingController();

  int get total => widget.total;

  @override
  void dispose() {
    for (final c in [_pagoCon, _referencia, _dolares, _tc, _mEf, _mTa, _mTr, _mVa, _mUsd, _mCr]) {
      c.dispose();
    }
    super.dispose();
  }

  int _tipoCambio() => leerPesos(_tc.text) ?? repos.ajustes.entero(Ajuste.tipoCambio);
  int _usdAPesos(String t) => ((leerCantidad(t) ?? 0) * _tipoCambio()).round();
  int _p(TextEditingController c) => leerPesos(c.text) ?? 0;

  /// Lo que no es efectivo en el pago mixto.
  int get _mOtros => _p(_mTa) + _p(_mTr) + _p(_mVa) + _usdAPesos(_mUsd.text) + _p(_mCr);

  /// (pago, mensaje de error)
  (Pago?, String?) _armarPago() {
    switch (_forma) {
      case _Forma.efectivo:
        final recibido = _pagoCon.text.trim().isEmpty ? total : leerPesos(_pagoCon.text);
        if (recibido == null) return (null, 'Escribe con cuánto paga.');
        if (recibido < total && !repos.ajustes.si(Ajuste.permitirCobroMenor)) {
          return (null, 'Faltan ${formatoPesos(total - recibido)}. Usa "Mixto" para pagar una parte con tarjeta o transferencia.');
        }
        return (Pago(efectivoCentavos: total, recibidoCentavos: recibido), null);
      case _Forma.tarjeta:
        return (Pago(tarjetaCentavos: total, referencia: _referencia.text.trim()), null);
      case _Forma.transferencia:
        return (Pago(transferenciaCentavos: total, referencia: _referencia.text.trim()), null);
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
        final cr = _p(_mCr);
        if (cr > 0 && _cliente == null) return (null, 'Para dejar una parte a crédito elige el cliente.');
        final otros = _mOtros;
        if (otros > total) return (null, 'Tarjeta, transferencia, vales, dólares y crédito suman más que el total.');
        final faltaEfectivo = total - otros;
        // Vacío = paga exacto el resto en efectivo.
        final ef = _mEf.text.trim().isEmpty ? faltaEfectivo : _p(_mEf);
        if (ef < faltaEfectivo) return (null, 'Faltan ${formatoPesos(faltaEfectivo - ef)}.');
        return (
          Pago(
            efectivoCentavos: faltaEfectivo,
            recibidoCentavos: ef,
            tarjetaCentavos: _p(_mTa),
            transferenciaCentavos: _p(_mTr),
            valesCentavos: _p(_mVa),
            dolaresCentavos: _usdAPesos(_mUsd.text),
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
        return (leerPesos(_pagoCon.text) ?? total) - total;
      case _Forma.dolares:
        return _usdAPesos(_dolares.text) - total;
      case _Forma.mixto:
        return _mEf.text.trim().isEmpty ? 0 : _p(_mEf) - (total - _mOtros);
      default:
        return 0;
    }
  }

  Future<void> _terminar(bool imprimir) async {
    final (pago, error) = _armarPago();
    if (pago == null) return aviso(context, error!);
    final c = _cliente;
    if (pago.creditoCentavos > 0 && c != null && c.tieneLimite) {
      final nuevo = c.saldoCentavos + pago.creditoCentavos;
      if (nuevo > c.limiteCentavos) {
        final ok = await confirmar(
            context,
            'Tope de crédito rebasado',
            '${c.nombre} tiene un tope de ${formatoPesos(c.limiteCentavos)} y ya debe ${formatoPesos(c.saldoCentavos)}.\n'
                'Con esta venta debería ${formatoPesos(nuevo)}: se pasa por ${formatoPesos(nuevo - c.limiteCentavos)}.\n\n'
                'Solo un supervisor puede autorizarlo.',
            si: 'Autorizar',
            peligro: true);
        if (!ok || !mounted || !await autorizar(context, Permiso.clientes)) return;
      } else if (c.alertaCredito(porcentajeAvisoCredito(repos.ajustes), extraCentavos: pago.creditoCentavos).isNotEmpty) {
        final pct = (nuevo * 100 / c.limiteCentavos).round();
        final ok = await confirmar(
            context,
            '${c.nombre} está por llegar a su tope',
            'Con esta venta deberá ${formatoPesos(nuevo)} de su tope de ${formatoPesos(c.limiteCentavos)} ($pct %).\n'
                'Le quedarán ${formatoPesos(c.limiteCentavos - nuevo)} de crédito.',
            si: 'Continuar');
        if (!ok) return;
      }
      if (!mounted) return;
    }
    final usd = _forma == _Forma.dolares ? _usdAPesos(_dolares.text) : 0;
    Navigator.pop(
      context,
      ResultadoCobro(
        pago: pago,
        imprimir: imprimir,
        cliente: c,
        notas: [_notas.trim(), if (usd > total) 'Cambio en pesos: ${formatoPesos(usd - total)}']
            .where((x) => x.isNotEmpty)
            .join(' · '),
      ),
    );
  }

  Future<void> _elegirCliente() async {
    final c = await elegirCliente(context);
    if (c != null) setState(() => _cliente = c.id.isEmpty ? null : c);
  }

  Future<void> _pedirNotas() async {
    final t = await pedirTexto(context, 'Notas del ticket', etiqueta: 'Notas', inicial: _notas);
    if (t != null) setState(() => _notas = t);
  }

  @override
  Widget build(BuildContext context) {
    final formas = [
      _Forma.efectivo,
      _Forma.tarjeta,
      _Forma.transferencia,
      if (repos.ajustes.si(Ajuste.usarCredito)) _Forma.credito,
      if (repos.ajustes.si(Ajuste.aceptarVales)) _Forma.vales,
      if (repos.ajustes.si(Ajuste.aceptarDolares)) _Forma.dolares,
      _Forma.mixto,
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () => _terminar(true),
        const SingleActivator(LogicalKeyboardKey.f2): () => _terminar(false),
        const SingleActivator(LogicalKeyboardKey.f4): _pedirNotas,
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
      },
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: anchoDialogo(context, 1040),
          height: altoDialogo(context, 640),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  color: ExColor.banda,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  child: Text('COBRAR', style: ExTexto.titulo(22, color: ExColor.bandaTexto)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Center(child: Text(formatoPesos(total), style: ExTexto.titulo(72, color: ExColor.indigo))),
                      const SizedBox(height: 8),
                      Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                        for (final f in formas) _boton(f),
                      ]),
                      const SizedBox(height: 22),
                      _campos(),
                    ]),
                  ),
                ),
              ]),
            ),
            // Columna derecha.
            Container(
              width: 290,
              color: ExColor.concreto,
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _accion(Icons.print_outlined, 'F1 - Cobrar e Imprimir', () => _terminar(true), principal: true),
                const SizedBox(height: 10),
                _accion(Icons.point_of_sale, 'F2 - Cobrar sin imprimir', () => _terminar(false)),
                const SizedBox(height: 10),
                _accion(Icons.close, 'ESC - Cancelar', () => Navigator.pop(context)),
                const SizedBox(height: 28),
                _accion(Icons.note_add_outlined, 'F4 - Ingresar notas', _pedirNotas),
                if (_notas.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_notas, style: const TextStyle(color: ExColor.texto2)),
                  ),
                const Spacer(),
                const Text('Total de artículos:', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: ExColor.indigo)),
                Text(formatoCantidad(widget.articulos), textAlign: TextAlign.center, style: ExTexto.titulo(34, color: ExColor.indigo)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _accion(IconData i, String t, VoidCallback f, {bool principal = false}) => SizedBox(
        height: 58,
        child: principal
            ? FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: ExColor.acento, foregroundColor: ExColor.tinta),
                onPressed: f,
                icon: Icon(i),
                label: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              )
            : OutlinedButton.icon(
                style: OutlinedButton.styleFrom(backgroundColor: ExColor.blanco),
                onPressed: f,
                icon: Icon(i),
                label: Text(t, style: const TextStyle(fontSize: 15)),
              ),
      );

  Widget _boton(_Forma f) {
    final sel = _forma == f;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _forma = f),
      child: Container(
        width: 112,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: sel ? ExColor.indigo : ExColor.blanco,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? ExColor.indigo : ExColor.linea),
        ),
        child: Column(children: [
          Icon(_iconos[f], size: 38, color: sel ? ExColor.blanco : ExColor.indigo),
          const SizedBox(height: 6),
          Text(_nombres[f]!, style: TextStyle(fontSize: 15, color: sel ? ExColor.blanco : ExColor.tinta)),
        ]),
      ),
    );
  }

  /// "Pagó con:" / "Su cambio:" grandes.
  Widget _renglonGrande(String etiqueta, Widget valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 170, child: Text(etiqueta, textAlign: TextAlign.right, style: ExTexto.titulo(24))),
          const SizedBox(width: 14),
          Expanded(child: valor),
        ]),
      );

  Widget _campoGrande(TextEditingController c, {bool autofocus = false}) => TextField(
        controller: c,
        autofocus: autofocus,
        style: ExTexto.mono(30, color: ExColor.indigo, peso: FontWeight.w600),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,$]'))],
        decoration: const InputDecoration(prefixText: '\$ '),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _terminar(true),
      );

  Widget _cambioGrande() {
    final c = _cambio();
    return _renglonGrande(
      c < 0 ? 'Faltan:' : 'Su cambio:',
      Text(formatoPesos(c.abs()), style: ExTexto.mono(34, color: c < 0 ? ExColor.rojo : ExColor.verde, peso: FontWeight.w700)),
    );
  }

  Widget _panelCliente({bool obligatorio = false}) {
    final c = _cliente;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: obligatorio && c == null ? ExColor.acento : ExColor.linea, width: obligatorio && c == null ? 2 : 1),
      ),
      child: Row(children: [
        const Icon(Icons.person_outline, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: c == null
              ? const Text('Elige el cliente', style: TextStyle(fontSize: 16))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  Text('Debe ${formatoPesos(c.saldoCentavos)}'
                      '${c.tieneLimite ? ' de ${formatoPesos(c.limiteCentavos)} · Disponible ${formatoPesos(c.disponibleCentavos)}' : ' · Sin tope'}',
                      style: const TextStyle(color: ExColor.texto2)),
                  if (c.alertaCredito(porcentajeAvisoCredito(repos.ajustes)).isNotEmpty)
                    Text(c.alertaCredito(porcentajeAvisoCredito(repos.ajustes)) == 'alcanzado'
                        ? 'Ya llegó a su tope de crédito'
                        : 'Cerca de su tope de crédito (${c.usoCredito} %)',
                        style: const TextStyle(color: ExColor.rojo, fontWeight: FontWeight.w700)),
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
        return Column(children: [
          _renglonGrande('Pagó con:', _campoGrande(_pagoCon, autofocus: true)),
          _cambioGrande(),
        ]);
      case _Forma.tarjeta:
      case _Forma.transferencia:
        return Column(children: [
          Text(_forma == _Forma.tarjeta ? 'Cobra en la terminal y anota la autorización (opcional).' : 'Revisa que te llegó la transferencia.',
              style: const TextStyle(fontSize: 16, color: ExColor.texto2)),
          const SizedBox(height: 12),
          TextField(
            controller: _referencia,
            autofocus: true,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
                labelText: _forma == _Forma.tarjeta ? 'Autorización / referencia' : 'Folio o referencia de la transferencia'),
            onSubmitted: (_) => _terminar(true),
          ),
        ]);
      case _Forma.vales:
        return const Text('Se cobra el total con vales de despensa. Los vales no dan cambio.', style: TextStyle(fontSize: 16));
      case _Forma.dolares:
        return Column(children: [
          Row(children: [
            Expanded(
                child: CampoNumero(
                    controller: _dolares,
                    etiqueta: 'Dólares recibidos (USD)',
                    autofocus: true,
                    onChanged: recalcular,
                    onSubmitted: (_) => _terminar(true))),
            const SizedBox(width: 12),
            Expanded(child: CampoNumero(controller: _tc, etiqueta: 'Tipo de cambio (\$ por dólar)', onChanged: recalcular)),
          ]),
          const SizedBox(height: 8),
          Text('Total en dólares: ${(total / _tipoCambio()).toStringAsFixed(2)} USD', style: const TextStyle(fontSize: 16)),
          _cambioGrande(),
        ]);
      case _Forma.credito:
        return _panelCliente(obligatorio: true);
      case _Forma.mixto:
        Widget fila(String t, TextEditingController c, {bool foco = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 170, child: Text(t, textAlign: TextAlign.right, style: const TextStyle(fontSize: 17))),
                const SizedBox(width: 12),
                SizedBox(width: 200, child: CampoNumero(controller: c, etiqueta: '', autofocus: foco, onChanged: recalcular)),
              ]),
            );
        final resta = total - _mOtros;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Reparte el pago. Lo que no cubran los demás se paga en efectivo.', style: TextStyle(color: ExColor.texto2)),
          const SizedBox(height: 8),
          fila('Tarjeta:', _mTa, foco: true),
          fila('Transferencia:', _mTr),
          if (repos.ajustes.si(Ajuste.aceptarVales)) fila('Vales:', _mVa),
          if (repos.ajustes.si(Ajuste.aceptarDolares)) fila('Dólares (USD):', _mUsd),
          if (repos.ajustes.si(Ajuste.usarCredito)) fila('A crédito:', _mCr),
          const Divider(height: 24),
          _renglonGrande('Efectivo:', Text(formatoPesos(resta < 0 ? 0 : resta), style: ExTexto.mono(26, peso: FontWeight.w600))),
          _renglonGrande('Pagó con:', _campoGrande(_mEf)),
          _cambioGrande(),
          if (_p(_mCr) > 0) ...[const SizedBox(height: 8), _panelCliente(obligatorio: true)],
        ]);
    }
  }
}
