QFLUSH (A-11) VSIX — README

Présentation

Ce projet fournit un squelette d’extension Visual Studio (VSIX) pour intégrer l’interface A‑11 (AlphaOnze) dans une Tool Window via WebView2. Le contrôle charge l’UI frontend (par défaut http://localhost:5173/) dans un panneau dockable nommé « QFLUSH (A-11) ».

Emplacement du projet

- Dossier du prototype VSIX : `tools/qflush-vsix/`
- Fichiers principaux :
  - `Qflush.A11.csproj`
  - `QflushToolWindowControl.xaml` + `.xaml.cs` (WebView2 host)
  - `QflushToolWindow.cs` (ToolWindowPane)
  - `QflushToolWindowCommand.cs` (commande menu)
  - `source.extension.vsixmanifest`

Prérequis

- Windows 10/11
- Visual Studio 2022 (édition Community/Professional/Enterprise)
- .NET Framework 4.8 (ou ciblé dans le .csproj)
- WebView2 Runtime installé (Evergreen Runtime)
- NuGet : `Microsoft.Web.WebView2` (référence déjà présente dans le `.csproj`)

Étapes pour builder et lancer en debug

1. Démarrer le frontend A‑11
   - Ouvrir un terminal, aller dans `D:/A11/apps/web` et lancer :
     `npm install` (si nécessaire)
     `npm run dev`
   - Vérifier que `http://localhost:5173/` sert l’UI.

2. Ouvrir le projet VSIX
   - Ouvrir Visual Studio 2022.
   - Fichier > Ouvrir > Projet/Solution > ouvrir `tools/qflush-vsix/Qflush.A11.csproj`.
   - Restaurer les packages NuGet.

3. Lancer en mode expérimental
   - Appuyer sur F5 pour lancer une instance expérimentale de Visual Studio.
   - Dans l’instance expérimentale : View > Other Windows > QFLUSH (A-11).
   - La Tool Window doit charger l’URL `http://localhost:5173/` dans un WebView2.

Génération du .vsix

- Pour packager l’extension : Build -> Build Solution. Le `.vsix` sera généré selon la configuration Visual Studio (ou via msbuild si configuré).

Dépannage rapide

- WebView2 ne s’initialise pas : vérifier que le runtime WebView2 est installé.
- Page vide dans la Tool Window : vérifier que le frontend A‑11 tourne sur `http://localhost:5173/` et qu’il est accessible depuis le navigateur.
- Erreurs de build : restaurer NuGet, vérifier la TargetFramework et que Visual Studio a les workloads requis.

Sécurité et bonnes pratiques

- Ne pas embarquer de secrets dans l’extension.
- L’UI chargée dans WebView2 doit être servie localement en dev. Pour déployer, adaptez l’URL cible.

Notes de développement

- Le contrôleur dispatchera `WebView2.Source = new Uri("http://localhost:5173/");` par défaut.
- Pour changer l’URL, modifier `QflushToolWindowControl.xaml.cs`.

Contact / Référence

- Repo d’origine : https://github.com/jEFFLEZ/a11
- Auteur du prototype : Funesterie

---

Si tu veux, j’ajoute un script PowerShell qui ouvre Visual Studio et lance le projet VSIX en mode debug automatiquement. Veux‑tu ça ?