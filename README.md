# Obtenir un notebook standard (sans modules python supplémentaires)

Lancer la commande `notebook-get`. Ci-dessous, l'aide du programme:

```
Permet d'obtenir une instance de jupyter notebook sur le cluster, à la demande.
Possibilité de spécifier les ressources CPU, Mémoire, et Génériques.
L'instance de jupyter notebook obtenue sera exécutée dans le chemin courant (sauf si l'option `--directory` est utilisée), et aura donc accès à tous les fichiers et dossiers présents dans `$PWD`. A utiliser avec vigilance.

Usage: notebook-get [OPTIONS]

Options:
      --job-name <JOB_NAME>
          Nom du job pour identifier l'instance de notebook demandée. Obligatoire, pas de valeur par défaut. Si non spécifié, l'utilisateur devra l'entrer

      --threads <THREADS>
          Nombre de threads que le notebook pourrait être amené à utiliser au maximum. Par défaut, 1

      --gres <GRES>
          Ressources génériques SLURM que le notebook pourrait être amené à utiliser (ex: `--gres gpu:a100:2`). Aucune ressource générique par défaut

      --time <TIME>
          Durée d'exécution maximale du notebook. Par défaut, 24 heures. Au-delà de 24 heures, un mail sera envoyé à l'administrateur système avec votre nom d'utilisateur sur le cluster

      --mem <MEM>
          Quantité de mémoire nécessaire pour faire tourner le notebook. Par défaut, 1G

      --node <NODE>
          Nom du noeud spécifique à utiliser pour lancer la commande. Si non spécifié, le choix du noeud reviendra à SLURM en fonction des ressources disponibles et celles demandées

      --image <IMAGE>
          Nom de l'image singularity à utiliser (sans l'extension, ni le chemin du dossier parent. Résolu comme `/SINGULARITIES/{image}.sif`)

      --directory <DIRECTORY>
          Dossier d'exécution du notebook. Par défaut, `$PWD`

  -h, --help
          Print help (see a summary with '-h')
```

Comme vous pouvez le voir, aucune option n'est obligatoire.

## Options relatives aux ressources

Ce programme va lancer sbatch (en coulisses). Vous pouvez spécifier les options suivantes, qui représentent un sous-ensemble de ce qu'on peut lancer avec sbatch:

- `threads`: Nombre de coeurs CPU potentiellement utilisés par votre notebook.
- `gres`: Ressources génériques SLURM potentiellement utilisées par votre notebook. Peut être utilisé pour demander de la puissance de calcul GPU.
- `time`: Durée maximale pour laquelle le notebook sera disponible à compter du démarrage du job SLURM. Par défaut, 24 heures; au-delà, un mail sera envoyé à l'administrateur système.
- `mem`: Quantité de mémoire (RAM) utilisée au maximum par le notebook. Par défaut, 1G.

## Suivi des usages

Si l'option `--job-name` n'est pas spécifiée, un nom de job sera demandé à l'utilisateur dans une optique de traçabilité. L'utilisateur doit expliciter le nom et le type du projet qui l'amène à utiliser jupyter notebook. Le nom est libre, mais doit être suffisament explicite.

### Options spécifiques

Si vous souhaitez voir votre notebook exécuté dans un dossier en particulier, précisez-le avec l'option `--directory`.

Si votre notebook a besoin d'un noeud en particulier, précisez-le avec l'option `--node`.

Si votre notebook a des dépendances particulières, spécifiques à votre projet, vous pouvez spécifier le nom de l'image singularity à utiliser avec l'option `--image` (voir la section [suivante](#créer-sa-propre-image-pour-notebook-installation-de-modules-python-supplémentaires)).

# Créer sa propre image pour notebook (installation de modules python supplémentaires)

## Préparation

1. Charger en local l'image `/SINGULARITIES/jupyter-notebook-base.sif`, à placer dans le dossier courant avec au moins un fichier `requirements.txt` (liste de dépendances python).
2. Créer un fichier `pytorch.def` correspondant:
   ```def
   Bootstrap: localimage
   From: jupyter-notebook-base.sif

   %files
      requirements.txt /requirements.txt
   %post
      uv pip install -U -r /requirements.txt
   ```
3. Compiler l'image singularity: `singularity build --force --fakeroot pytorch.sif pytorch.def`
4. Charger sur le cluster, dans `/SINGULARITIES`, l'image résultante (ici, `pytorch.sif`)

## Utilisation d'une image notebook en particulier

Une fois terminée l'étape précédente de création d'une nouvelle image dédiée, vous pouvez l'utiliser au moment de l'appel de `notebook-get`:

```bash
notebook-get --image pytorch
```

Notez que la valeur `pytorch` sera résolue en `/SINGULARITIES/pytorch.sif`. Si le chemin n'existe pas, `sbatch` sera exécuté, mais le script sbatch échouera sans éxécuter singularity.

# Préparation du système (à l'attention des sys admin)

## Les dossiers requis (hard codés)

Un dossier partagé en NFS, nommé `/OPT`, accessible par tous les noeuds au même chemin, avec les sous-dossiers suivants:

`mkdir -p /OPT/notebooks/{batch-scripts,running,logs}`

Un dossier partagé en NFS, nommé `/SINGULARITIES`, accessible par tous les noeuds au même chemin:

`/SINGULARITIES`. Ce dossier doit contenir au moins un fichier nommé `/SINGULARITIES/jupyter-notebook-base.sif`.

## Les fichiers requis

### Le script sbatch

Dans `/OPT/notebooks/batch-scripts`, placer le fichier `notebook.sbatch` présent dans ce dossier (permissions recommandées: `root root 644`).

### L'exécutable notebook-get

C'est l'objet de ce dépôt git. Pour le configurer correctement, deux étapes simples:

1. Compiler `notebook-get`. Commande: `./build-linux-old.sh` (permet de compiler pour des anciennes versions de glibc).
2. Copier `./target/release/notebook-get` dans un chemin de `$PATH`. Commande: `cp ./target/release/notebook-get /usr/local/bin` (à exécuter en tant que root).
3. S'assurer que le fichier `/usr/local/bin/notebook-get` a bien les permissions `root root 755`.

### L'image singularity de base

Dans `/SINGULARITIES`, le fichier `jupyter-notebook-base.sif`. Pour l'obtenir, vous pouvez exécuter simplement `./notebook-build.sh`, qui va construire l'image singularity.
