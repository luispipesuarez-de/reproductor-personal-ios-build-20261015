# Reproductor personal para iPhone

Aplicación SwiftUI con búsqueda, reproducción nativa, cola y biblioteca local. Copia de código preparada para compilar con un runner estándar de macOS en GitHub Actions.

La revisión `5de4cd3` pasó 147 pruebas unitarias y 16 de interfaz, además de la compilación Release. Prioriza canciones de 3–10 minutos en búsqueda, recomendaciones y radio; conserva géneros personalizados y permite cerrar la cola con un deslizamiento del reproductor en pausa. Los tests usan datos controlados; Release usa el proveedor real. El IPA se genera sin firmar y requiere firma personal para instalarse.

En macOS con Xcode y XcodeGen:

```bash
bash scripts/ci.sh test
bash scripts/ci.sh ipa
```

Dependencia: [YouTubeKit](https://github.com/b5i/YouTubeKit), fijada en project.yml. Su licencia se incluye en ReproductorPersonal/Resources/YouTubeKit-LICENSE.txt.

## Entrega comprobada

Versión 0.1.0, compilación 7, iOS 16 o posterior. [Ejecución y artefacto ReproductorPersonal-27](https://github.com/luispipesuarez-de/reproductor-personal-ios-build-20261015/actions/runs/38997159679). El paquete está sin firmar. Las pruebas de contenido real en un dispositivo se realizan por separado. La selección opcional de un test en el workflow es de diagnóstico e impide empaquetar un IPA; la entrega requiere la suite completa.
