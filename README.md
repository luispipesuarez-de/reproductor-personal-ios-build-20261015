# Reproductor personal para iPhone

Aplicación SwiftUI con búsqueda, reproducción nativa, cola y biblioteca local. Copia de código preparada para compilar con un runner estándar de macOS en GitHub Actions.

La revisión `9850a39` pasó 71 pruebas unitarias y 4 de interfaz, además de la compilación Release. Incluye la preparación del contexto anónimo al reproducir elementos guardados después de reiniciar. Los tests usan datos controlados; Release usa el proveedor real. El IPA se genera sin firmar y requiere firma personal para instalarse.

En macOS con Xcode y XcodeGen:

```bash
bash scripts/ci.sh test
bash scripts/ci.sh ipa
```

Dependencia: [YouTubeKit](https://github.com/b5i/YouTubeKit), fijada en project.yml. Su licencia se incluye en ReproductorPersonal/Resources/YouTubeKit-LICENSE.txt.

## Entrega comprobada

Versión 0.1.0, compilación 5, iOS 16 o posterior. [Ejecución y artefacto ReproductorPersonal-4](https://github.com/luispipesuarez-de/reproductor-personal-ios-build-20261015/actions/runs/38813838217). El paquete está sin firmar. Las pruebas de contenido real en un dispositivo se realizan por separado.
