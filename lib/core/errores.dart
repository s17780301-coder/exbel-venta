/// Error de una regla del negocio (ej. "el cliente excede su límite").
/// Su mensaje se muestra tal cual al cajero.
class ErrorNegocio implements Exception {
  const ErrorNegocio(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}
