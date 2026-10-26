# Password Manager

Gestor local de contraseñas para **Windows**, desarrollado con Flutter/Dart como proyecto personal y de portfolio. Funciona sin servidor, cuenta remota, telemetría ni sincronización.

**Versión 0.3.0.** Funcionalidad local probada automáticamente y por el autor en Windows. Tiene revisión interna y límites documentados; no cuenta con auditoría externa ni certificación de seguridad. El cifrado no protege de un atacante que controle la sesión de Windows mientras se desbloquean o copian credenciales.

## Funciones

- Bóveda KDBX 4.0 con contraseña maestra y PIN de ocho dígitos para consultar, editar o eliminar cuentas.
- Consulta rápida de servicio, usuario y contraseña oculta, con botones de copia. Edición independiente e historial cifrado de hasta veinte versiones por cuenta.
- Generador criptográfico de 20 a 30 caracteres; sin símbolos por defecto, o con uno o dos símbolos opcionales.
- Guardado automático, copia cifrada de la versión anterior y detección de cambios externos.
- Cambio de contraseña maestra/PIN, exportación de copia cifrada y restauración validada conservando el archivo anterior.
- Bloqueo manual, por cinco minutos de inactividad, al minimizar, bloquear Windows con Win+L y suspender/reanudar.
- Limpieza del portapapeles de mejor esfuerzo a los 30 segundos o al bloquear, sin borrar el historial de Windows.

## Ejecutar en Windows

Requisitos: Git, Flutter 3.47.8 con Dart 3.13.7 y Visual Studio con Desarrollo para el escritorio con C++, CMake y Windows SDK. El proyecto exige Dart `^3.13.7`. Android no forma parte de esta entrega y no se necesita Android SDK.

```powershell
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter run -d windows -t lib/main.dart
```

Para compilar:

```powershell
flutter build windows --release -t lib/main.dart
```

El ejecutable se genera en `build/windows/x64/runner/Release/password_manager.exe`. Mantenerlo junto con las DLL y la carpeta `data` de esa salida. No se incluye un instalador ni firma de código.

## Demo para capturas

```powershell
flutter run -d windows -t tool/portfolio_demo.dart
```

La demo tiene marca **DEMO**, una cuenta de `example.com` y no accede a archivos de bóveda ni guarda cambios. Configurar un PIN ficticio, por ejemplo `12345678`. Usar solo cuentas inventadas y dominios `example.com`/`example.org`. La demo permite ilustrar la interfaz de cuentas; para capturas de apertura/restauración usar una bóveda separada con datos ficticios.

No publicar capturas de cuentas personales, portapapeles, rutas de usuario o ventanas de selección de archivos sin revisar. Las capturas no están incluidas automáticamente en el paquete de código.

## Uso y recuperación

1. Crear una bóveda con frase maestra exclusiva de al menos 16 caracteres y confirmar un PIN numérico de ocho dígitos. No hay recuperación por correo.
2. Agregar una cuenta y guardar. Tocar la tarjeta solicita PIN y permite consultar/copiar. El lápiz circular abre la edición; la papelera solicita confirmación.
3. En el menú de tres puntos se cambia la contraseña maestra/PIN o se guarda una copia cifrada. Elegir un nombre nuevo: no se sobrescriben archivos existentes.
4. En la pantalla bloqueada, Restaurar copia cifrada permite seleccionar `.kdbx`/`.bak` e ingresar la contraseña de esa copia. Reemplaza la bóveda actual, no mezcla cuentas, y conserva el archivo anterior con un nombre único.

La ubicación se gestiona internamente en `%LOCALAPPDATA%\PasswordManager\vault.kdbx`. No hay campo de ruta en la interfaz. Cada guardado de un archivo existente conserva la versión anterior en `.bak`; esa copia en el mismo disco no reemplaza una copia externa. Las copias previas a un cambio de contraseña conservan su contraseña/PIN anteriores.

Cambiar lo guardado en el gestor no cambia la contraseña del servicio externo. La pérdida de la contraseña maestra puede hacer irrecuperables los datos.

## Diseño y seguridad

KDBX 4.0, AES-256 y Argon2d con 64 MiB, tres iteraciones y un hilo. Biblioteca `kdbx` fijada en 2.5.0. Esa biblioteca no implementa Argon2id. No se implementó un algoritmo de cifrado propio.

El PIN está dentro del archivo cifrado y controla la interfaz después del descifrado: **no es un segundo factor criptográfico**. Cinco fallos activan una espera local de treinta segundos, tanto para PIN como para apertura/restauración. Reiniciar restablece los límites; estos no frenan ataques sin conexión contra un archivo copiado.

La contraseña maestra no se escribe a disco. Mientras la bóveda está abierta hay secretos en memoria; Dart no garantiza su borrado inmediato. Los archivos temporales, copias e historial están cifrados. El historial usa un campo protegido propio, no el historial nativo KeePass. Solo se admiten bóvedas de esta aplicación con su perfil KDF; no es un importador general de KeePass.

El portapapeles es el normal de Windows. Se intenta limpiar si el contenido aún coincide; el temporizador no continúa tras terminar el proceso. **Win+V → Borrar todo** limpia el historial salvo elementos anclados; eliminarlos por separado y copiar después un texto inocuo reemplaza el contenido actual. Se puede desactivar historial/sincronización en Configuración → Sistema → Portapapeles.

Ver [SECURITY.md](SECURITY.md) y [revisión interna](docs/SECURITY_REVIEW.md).

## Pruebas reproducibles

La suite cubre persistencia, contraseña incorrecta, contenido alterado, guardado fallido, conflictos externos, cambios de credenciales, exportación/restauración, historial, validaciones, PIN, generador, portapapeles simulado y eventos de bloqueo. Incluye pruebas de cabeceras truncadas, perfiles KDF no admitidos y límite de tamaño.

```powershell
flutter test
powershell -File tool/check_dependencies.ps1
```

El segundo comando consulta OSV enviando solo nombres/versiones públicos del lockfile. Requiere conexión y no analiza secretos, código nativo, Windows o vulnerabilidades desconocidas.

La verificación cruzada con PyKeePass realizada antes del historial se reproduce opcionalmente con:

```powershell
python -m pip install --target build/verification_deps pykeepass==4.2.0
dart run tool/interop.dart create
python tool/verify_kdbx.py
dart run tool/interop.dart verify
```

Los scripts usan únicamente una fixture ficticia con contraseña pública bajo `build/interop/`; nunca una bóveda personal. No se afirma haber repetido esa verificación para la versión actual.

## Publicación

Ver [guía para GitHub](docs/PUBLISHING.md). `tool/package_portfolio.ps1` crea una selección de código fuente, un manifiesto SHA-256 y un ZIP en `dist/`, sin publicar ni subir nada. No incluye bóvedas, Android, compilaciones, caches ni los documentos locales de transferencia.

## Licencia

Código propio bajo **GPL-3.0**, compatible con la dependencia `kdbx` 2.5.0. Ver [LICENSE](LICENSE) y [avisos de terceros](THIRD_PARTY_NOTICES.md). Los componentes de terceros conservan sus licencias. Si se distribuyen binarios, revisar las obligaciones de distribución del código fuente correspondiente; el paquete para GitHub preparado aquí es de fuentes.
