import 'dart:io';

import 'package:exbel_venta/core/licencia.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('código de activación por equipo', () {
    final c = codigoActivacionPara('AB12-CD34');
    expect(c, matches(RegExp(r'^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$')));
    expect(codigoActivacionPara('ab12cd34'), c);
    expect(codigoActivacionPara('AB12-CD35'), isNot(c));
  });

  test('prueba de 7 días y activación', () async {
    final dir = await Directory.systemTemp.createTemp('lic');
    final e = await Licencia.instancia.cargar(dir);
    expect(e.activada, isFalse);
    expect(e.diasRestantes, diasDePrueba);
    expect(await Licencia.instancia.activar('0000-0000-0000'), isFalse);
    expect(await Licencia.instancia.activar(codigoActivacionPara(e.equipo).toLowerCase()), isTrue);
    expect((await Licencia.instancia.cargar(dir)).activada, isTrue);
  });
}
