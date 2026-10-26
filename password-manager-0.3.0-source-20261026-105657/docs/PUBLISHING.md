# Publicar en GitHub sin incluir datos personales

## Paquete recomendado

El ZIP de fuentes producido por `tool/package_portfolio.ps1` incluye solamente:

- `lib/`, `test/`, `tool/` y las fuentes Windows sin `windows/flutter/ephemeral/`.
- `pubspec.yaml`, `pubspec.lock`, configuración de análisis y metadatos del proyecto.
- README, LICENSE, SECURITY, CHANGELOG, avisos de terceros y esta carpeta `docs/`.
- `.gitignore` y un manifiesto de integridad de los archivos seleccionados.

No incluye `build/`, `.dart_tool/`, `dist/`, `.git/`, `.vscode/`, `.vs/`, Android, SDKs, paquetes descargados, credenciales, bóvedas, copias, temporales ni documentos de transferencia locales. El scanner usa patrones; no reemplaza la revisión humana.

## Pasos

1. Extraer el ZIP de fuentes en una carpeta nueva. Revisar su contenido y cualquier captura antes de subirlo.
2. Crear un repositorio vacío en GitHub, sin inicializarlo con otro README o licencia.
3. Desde la carpeta extraída:

```powershell
git init
git add .
git status --short
git diff --cached --stat
```

Revisar la lista: no debe haber `.kdbx`, `.bak`, `.pending`, archivos de claves, caches, compilaciones ni cuentas personales. El ZIP usa una lista de selección y `.gitignore` ayuda con cambios futuros; Git puede rastrear archivos ignorados si alguien los agrega a la fuerza. No reutilizar un historial que haya tenido secretos.

4. Solo después de esa revisión:

```powershell
git commit -m "Prepare Windows portfolio version 0.3.0"
git branch -M main
git remote add origin URL_DE_TU_REPOSITORIO
git push -u origin main
```

Configurar nombre/correo de Git antes del commit si hace falta. Un commit público muestra esos datos: usar un correo noreply de GitHub si no se quiere publicar el personal. No se configura automáticamente identidad ni remoto.

5. Activar detección de secretos/protección de push y reportes privados de vulnerabilidades si están disponibles para el repositorio. No autorizar un aviso de secreto sin revisar su origen.

## Capturas

Ejecutar `flutter run -d windows -t tool/portfolio_demo.dart` para las pantallas de cuentas con datos ficticios y marca DEMO. No abre bóvedas personales. Para las pantallas de creación/restauración utilizar una bóveda ficticia separada. No publicar tus capturas anteriores si contienen usuarios/correos reales.

Revisar también barra de tareas, notificaciones, nombre de usuario del sistema, cuadros de archivos, metadatos y texto de las imágenes. Las capturas no se agregan ni se copian automáticamente al paquete.

## Código público y versión descargable

Publicar código no revela la contraseña maestra ni las credenciales: no están incluidas. Tampoco deben publicarse archivos cifrados reales: un tercero puede conservarlos e intentar descifrarlos sin conexión. El formato y los parámetros criptográficos no son secretos.

Para empezar, publicar el código. Si se desea ofrecer un ejecutable en GitHub Releases, preparar aparte un ZIP con la carpeta release completa, versión y checksum, avisos/licencias y acceso al código fuente correspondiente. No subir toda la carpeta `build/` al repositorio ni afirmar que el ejecutable está firmado o auditado.

## Actualizaciones

Para repetir el empaquetado desde un proyecto con herramientas disponibles:

```powershell
powershell -File tool/package_portfolio.ps1
```

Los artefactos se generan en `dist/`, excluido de Git. El script no inicializa repositorios, no crea commits y no publica nada.
