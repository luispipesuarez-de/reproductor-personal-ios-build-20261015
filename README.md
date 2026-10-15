# Reproductor personal para iPhone

Aplicación SwiftUI con búsqueda, reproducción nativa, cola y biblioteca local. Copia de código preparada para compilar con un runner estándar de macOS en GitHub Actions.

La verificación de esta revisión está pendiente. Los tests usan datos controlados; Release usa el proveedor real. El IPA se genera sin firmar y requiere firma personal para instalarse.

En macOS con Xcode y XcodeGen:

```bash
bash scripts/ci.sh test
bash scripts/ci.sh ipa
```

Dependencia: [YouTubeKit](https://github.com/b5i/YouTubeKit), fijada en project.yml. Su licencia se incluye en ReproductorPersonal/Resources/YouTubeKit-LICENSE.txt.
