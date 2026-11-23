/// Texto para buscar: minúsculas y sin acentos ("Azúcar" -> "azucar").
String sinAcentos(String s) {
  const cambios = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n', 'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u'};
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(cambios[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Lo que se guarda en productos.busqueda.
String textoBusqueda(String descripcion, String codigo) => sinAcentos('$descripcion $codigo');
