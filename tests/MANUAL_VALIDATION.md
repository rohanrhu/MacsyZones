# Validation manuelle des Spaces et écrans

Les tests automatisés valident l'état de déplacement, les invariants AX et les
builds. Mission Control et les permissions Accessibility exigent toutefois une
validation interactive sur une session macOS réelle.

1. Donner à la version testée la permission Accessibility, puis la lancer dans
   le Space 1.
2. Dans le Space 1, tester `déplacement → Shift`, puis `Shift → déplacement`.
   Les mêmes zones et le même comportement doivent apparaître.
3. Passer au Space 2 sans relancer MacsyZones et refaire les deux ordres. Tester
   une application déjà ouverte dans ce Space avant le lancement de MacsyZones.
4. Revenir au Space 1 et confirmer que le déplacement fonctionne toujours.
5. Lancer une nouvelle application, créer une seconde fenêtre, fermer cette
   fenêtre, puis en recréer une. Chacune doit être détectée sans relance.
6. Affecter des layouts différents aux Spaces 1 et 2 et confirmer que le layout
   correspondant est sélectionné à chaque transition.
7. Avec deux écrans, affecter un layout distinct à chaque couple écran/Space,
   puis déplacer une fenêtre entre écrans et Spaces.
8. Répéter les étapes avec l'activation par clic droit et avec un layout Grid.
9. Naviguer rapidement Space 1 → Space 2 → Space 1. Un callback retardé ne doit
   pas réappliquer le layout du Space 2.
10. Vérifier enfin les fenêtres plein écran et confirmer qu'aucun overlay ne
    reste visible après le relâchement de la souris ou de la Snap Key.

Pour exécuter toute la validation automatisée :

```sh
tests/run_full_validation.sh
```
