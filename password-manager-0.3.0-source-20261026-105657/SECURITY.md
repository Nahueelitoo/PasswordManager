# Seguridad

## Alcance

Password Manager 0.3.0 es un proyecto personal para Windows con revisión interna y pruebas reproducibles. No está auditado externamente ni certificado. No afirmar que es invulnerable o que custodia secretos con garantías comerciales.

## Modelo de amenaza

Se busca proteger cuentas guardadas frente a la lectura de archivos locales o copias sin conocer una frase maestra fuerte, detectar manipulación y evitar perder la única versión ante fallos comunes de guardado. La sesión abierta, el sistema operativo, el portapapeles y el equipo del usuario son parte del entorno de confianza.

No se garantiza resistencia a malware, procesos con acceso al usuario/administrador, captura de teclado/pantalla, análisis de memoria o fallos físicos del disco. La limpieza de memoria y el borrado físico no están garantizados por Dart o el sistema de archivos.

El PIN es una barrera de interfaz, no un segundo factor criptográfico. El límite de intentos es local a la sesión y no protege archivos copiados. Las copias e historial conservan datos antiguos cifrados. No hay backend, CORS, JWT, OAuth ni API de red.

## Informar problemas

No adjuntar bóvedas, contraseñas, PIN, tokens, archivos de volcado o capturas con cuentas reales a issues públicos. Reproducir con datos ficticios. Si el repositorio tiene habilitado Private vulnerability reporting, utilizar Security → Report a vulnerability para detalles explotables. De lo contrario, abrir un issue sin el exploit ni secretos solicitando un canal privado; todavía no se ha configurado un contacto de seguridad dedicado.

Incluir versión, Windows, pasos con fixture ficticia e impacto observado. Los reportes y pruebas se revisan antes de modificar datos de usuarios.

## Verificación

Ver docs/SECURITY_REVIEW.md. Las pruebas automatizadas, el análisis estático y una consulta sin avisos en OSV no equivalen a una auditoría independiente ni a ausencia de vulnerabilidades.
