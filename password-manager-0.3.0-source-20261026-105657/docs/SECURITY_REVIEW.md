# Revisión interna de seguridad — versión 0.3.0

Fecha: 2026-10-26. Alcance: fuentes Dart/Windows, pruebas automatizadas con datos ficticios y comprobaciones de preparación para publicación. Revisión interna realizada con asistencia de Codex; no es independiente ni certifica ausencia de vulnerabilidades.

Resultado final de esta preparación: **39 pruebas aprobadas**, análisis estático sin problemas y compilación release de Windows 0.3.0 correcta. La consulta OSV se completó para 50 paquetes hosted sin avisos reportados. El empaquetador seleccionó y revisó heurísticamente 61 archivos de fuentes; el manifiesto SHA-256 no tuvo diferencias. Las contraseñas y PIN públicos presentes en fixtures son ficticios y deliberados.

## Resultados y pruebas

- Persistencia y cifrado: datos ficticios guardados/reabiertos, búsqueda de cadenas ficticias legibles en el archivo cifrado y rechazo de contraseña incorrecta/contenido alterado.
- Guardado y recuperación: fallos de copia anterior conservan archivo/memoria; conflictos externos no se sobrescriben; exportación no reemplaza archivos existentes; restauración valida la copia y conserva la bóveda previa.
- Credenciales e historial: cambios fallidos preservan contraseña/PIN anteriores; nuevas credenciales persisten; historial cifrado se conserva al reabrir y tiene veinte versiones como máximo.
- Autorización local: PIN para consultar/editar/eliminar; espera local tras cinco fallos; no hay tokens, servidor, API HTTP ni CORS.
- Ciclo de vida: avisos de ocultar y de bloqueo de sesión simulados durante creación/guardado; retiro inmediato de diálogos sensibles y bloqueo al completar operaciones.
- Entradas: límites de tamaño, campos requeridos, caracteres nulos e identificadores duplicados rechazados antes de modificar el archivo.
- Límites de archivos: pruebas de cabeceras truncadas, perfiles KDF no admitidos y archivo superior a 16 MiB. No se intenta ejecutar un KDF con costos hostiles ni se usan secretos reales.
- Portapapeles: pruebas con plataforma simulada de copia/limpieza y finalización de copia pendiente al disponer el controlador. No se promete borrar el historial de Windows.
- Dependencias: consulta OSV de 50 paquetes hosted y sus versiones exactas del lockfile, sin avisos reportados en esa consulta. No cubre vulnerabilidades desconocidas, Flutter/Dart, Windows ni un examen independiente del código de cada dependencia.
- Publicación: selección de fuentes con exclusión de bóvedas, copias, temporales, claves y archivos generados; búsqueda heurística de tokens, claves privadas, rutas personales y correos personales. No es un escáner exhaustivo de secretos.

## Comprobación manual informada por el autor

Funcionan creación/apertura, consulta/copia, edición, eliminación, exportación y restauración, cambio de contraseña maestra y PIN, persistencia al cerrar/abrir, bloqueo al minimizar, Win+L y suspensión/reanudación. Esta evidencia manual no se presenta como una automatización de la interfaz nativa.

## Límites y trabajo adicional

- No hay auditoría independiente, fuzzing continuo, análisis forense de memoria, pruebas de cortes físicos de energía ni certificación.
- Un proceso que controle Windows puede capturar memoria, teclado, pantalla o portapapeles durante el uso. Dart no garantiza borrado inmediato de secretos.
- PIN y límites de intentos son de interfaz/sesión. No frenan el descifrado offline de una copia robada. Las copias antiguas conservan las credenciales antiguas.
- KDBX 4/AES-256/Argon2d, no Argon2id. La aplicación usa APIs internas de `kdbx` fijadas por versión para limitar parámetros antes de derivar claves.
- La interoperabilidad previa con PyKeePass se hizo antes de introducir historial; no se afirma haber verificado la versión actual con esa implementación.
- El ejecutable no está firmado ni se distribuye con instalador. Se recomienda una revisión externa de AppSec/criptografía aplicada si se pretende custodiar secretos críticos o distribuirlo como producto de seguridad.

Para un portfolio, presentar el alcance y los resultados tal como son, junto con las pruebas reproducibles, es más útil que afirmar «100 % seguro» o inventar certificaciones.

## Reproducción

```powershell
flutter analyze
flutter test
powershell -File tool/check_dependencies.ps1
powershell -File tool/package_portfolio.ps1
```

La comprobación de dependencias requiere red y solo envía nombres/versiones públicos. Empaquetar no publica ni sube nada. Ver SECURITY.md para reportar hallazgos sin compartir secretos.
