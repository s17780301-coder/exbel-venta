import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../data/ajustes_repo.dart';
import '../../data/ejemplo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../comun/ex_widgets.dart';
import '../comun/ventana.dart';
import '../principal.dart';
import '../sesion.dart';
import '../tema/tema.dart';

/// Entrada del cajero: primera configuración, contraseña y fondo de caja.
class AccesoPage extends StatefulWidget {
  const AccesoPage({super.key});

  @override
  State<AccesoPage> createState() => _AccesoPageState();
}

enum _Paso { cargando, primeraVez, entrar, fondo }

class _AccesoPageState extends State<AccesoPage> {
  _Paso _paso = _Paso.cargando;
  final _tienda = TextEditingController();
  final _nombre = TextEditingController();
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  final _clave2 = TextEditingController();
  final _fondo = TextEditingController();
  final _focoClave = FocusNode();
  bool _ejemplo = true;
  bool _ocupado = false;
  Cajero? _cajero;
  List<Cajero> _cajeros = [];

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    for (final c in [_tienda, _nombre, _usuario, _clave, _clave2, _fondo]) {
      c.dispose();
    }
    _focoClave.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final hay = await repos.cajeros.hayCajeros();
    _cajeros = hay ? await repos.cajeros.listar() : [];
    if (!mounted) return;
    setState(() {
      _paso = hay ? _Paso.entrar : _Paso.primeraVez;
      _clave.clear();
      if (_cajeros.length == 1) _usuario.text = _cajeros.first.usuario;
    });
  }

  Future<void> _crearAdministrador() async {
    if (_clave.text != _clave2.text) return aviso(context, 'Las contraseñas no coinciden.');
    setState(() => _ocupado = true);
    await intentar(context, () async {
      if (_tienda.text.trim().isNotEmpty) await repos.ajustes.guardar(Ajuste.nombreNegocio, _tienda.text.trim());
      final c = await repos.cajeros.guardar(
          usuario: _usuario.text, nombre: _nombre.text, clave: _clave.text, administrador: true);
      if (_ejemplo) await cargarEjemplo(cajeroId: c.id);
      _cajero = c;
      await _despuesDeEntrar();
    });
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _entrar() async {
    setState(() => _ocupado = true);
    final c = await repos.cajeros.entrar(_usuario.text, _clave.text);
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (c == null) {
      _clave.clear();
      _focoClave.requestFocus();
      return aviso(context, 'Usuario o contraseña incorrectos.');
    }
    _cajero = c;
    await _despuesDeEntrar();
  }

  Future<void> _despuesDeEntrar() async {
    final t = await repos.caja.turnoAbierto();
    if (!mounted) return;
    if (t != null) return _irAPrincipal(t);
    _fondo.text = (repos.ajustes.entero(Ajuste.fondoSugerido) / 100).toStringAsFixed(2);
    setState(() => _paso = _Paso.fondo);
  }

  Future<void> _abrirTurno() async {
    final fondo = leerPesos(_fondo.text) ?? 0;
    await intentar(context, () async {
      final t = await repos.caja.abrirTurno(_cajero!.id, fondo);
      _irAPrincipal(t);
    });
  }

  void _irAPrincipal(Turno t) {
    sesion.entrar(_cajero!, t);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Principal()));
  }

  @override
  Widget build(BuildContext context) {
    final negocio = repos.ajustes.texto(Ajuste.nombreNegocio);
    return Scaffold(
      body: Row(children: [
        // Panel de marca.
        Expanded(
          flex: 5,
          child: Container(
            color: ExColor.tinta,
            padding: const EdgeInsets.all(28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const ExMarca(oscuro: true, tamano: 15),
              const Spacer(),
              Text(_paso == _Paso.primeraVez ? 'Bienvenido a' : 'Punto de venta de',
                  style: ExTexto.texto(18, color: ExColor.textoClaro2)),
              const SizedBox(height: 6),
              Text(_paso == _Paso.primeraVez ? 'exBel venta' : negocio,
                  style: ExTexto.titulo(48, color: ExColor.concreto)),
              const SizedBox(height: 16),
              Container(width: 64, height: 6, color: ExColor.acento),
              const SizedBox(height: 16),
              Text('Ventas, inventario, crédito y cortes de caja.\nFunciona sin internet.',
                  style: ExTexto.texto(16, color: ExColor.textoClaro)),
              const Spacer(),
              Text(formatoFechaHora(DateTime.now()), style: ExTexto.mono(13, color: ExColor.textoClaro2)),
            ]),
          ),
        ),
        Expanded(
          flex: 6,
          child: Stack(children: [
            const Positioned(top: 8, right: 8, child: BotonesVentana()),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: SizedBox(width: 440, child: _formulario()),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _formulario() {
    switch (_paso) {
      case _Paso.cargando:
        return const Center(child: CircularProgressIndicator());
      case _Paso.primeraVez:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Empecemos', style: ExTexto.titulo(32)),
          const SizedBox(height: 6),
          const Text('Crea la cuenta del dueño (administrador). Después podrás dar de alta a tus cajeros.'),
          const SizedBox(height: 24),
          TextField(
              controller: _tienda,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre de la tienda', hintText: 'Abarrotes Lupita')),
          const SizedBox(height: 14),
          TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Tu nombre')),
          const SizedBox(height: 14),
          TextField(controller: _usuario, decoration: const InputDecoration(labelText: 'Usuario', hintText: 'admin')),
          const SizedBox(height: 14),
          TextField(controller: _clave, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña')),
          const SizedBox(height: 14),
          TextField(
              controller: _clave2,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repite la contraseña'),
              onSubmitted: (_) => _crearAdministrador()),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _ejemplo,
            onChanged: (v) => setState(() => _ejemplo = v ?? false),
            contentPadding: EdgeInsets.zero,
            title: const Text('Cargar departamentos y productos de ejemplo'),
            subtitle: const Text('Para practicar. Los puedes borrar o cambiar después.'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _ocupado ? null : _crearAdministrador, child: const Text('Crear y entrar')),
        ]);
      case _Paso.entrar:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Entrar a la caja', style: ExTexto.titulo(32)),
          const SizedBox(height: 24),
          if (_cajeros.length > 1) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in _cajeros)
                ChoiceChip(
                  label: Text(c.nombre),
                  avatar: ExAvatar(c.nombre, size: 22),
                  selected: _usuario.text == c.usuario,
                  onSelected: (_) {
                    setState(() => _usuario.text = c.usuario);
                    _focoClave.requestFocus();
                  },
                ),
            ]),
            const SizedBox(height: 16),
          ],
          TextField(
              controller: _usuario,
              autofocus: _cajeros.length != 1,
              decoration: const InputDecoration(labelText: 'Usuario'),
              onSubmitted: (_) => _focoClave.requestFocus()),
          const SizedBox(height: 14),
          TextField(
              controller: _clave,
              focusNode: _focoClave,
              autofocus: _cajeros.length == 1,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña'),
              onSubmitted: (_) => _entrar()),
          const SizedBox(height: 24),
          FilledButton(onPressed: _ocupado ? null : _entrar, child: const Text('Entrar')),
        ]);
      case _Paso.fondo:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Hola, ${_cajero?.nombre ?? ''}', style: ExTexto.titulo(32)),
          const SizedBox(height: 6),
          const Text('Abre tu turno. ¿Con cuánto dinero empieza la caja?'),
          const SizedBox(height: 24),
          CampoNumero(
              controller: _fondo,
              etiqueta: 'Fondo de caja (\$)',
              autofocus: true,
              onSubmitted: (_) => _abrirTurno()),
          const SizedBox(height: 24),
          FilledButton(onPressed: _abrirTurno, child: const Text('Abrir turno')),
          const SizedBox(height: 8),
          TextButton(onPressed: _iniciar, child: const Text('Cambiar de usuario')),
        ]);
    }
  }
}
