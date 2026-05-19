use anyhow::{Context, bail};
use clap::Parser;
use inquire::{Confirm, Text, validator::Validation};
use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::str::FromStr;
use std::thread::sleep;
use std::time::Duration;
use std::{path::Path, process::Command};

#[derive(Parser, Debug, Default)]
#[command(
    long_about = "Permet d'obtenir une instance de jupyter notebook sur le cluster, à la demande.\nPossibilité de spécifier les ressources CPU, Mémoire, et Génériques.\nL'instance de jupyter notebook obtenue sera exécutée dans le chemin courant (sauf si l'option `--directory` est utilisée), et aura donc accès à tous les fichiers et dossiers présents dans `$PWD`. A utiliser avec vigilance.",
    about = "Obtenir une instance de jupyter notebook sur le cluster."
)]
struct SlurmNoteBookArgs {
    /// Nom du job pour identifier l'instance de notebook demandée. Obligatoire, pas de valeur par défaut. Si non spécifié, l'utilisateur devra l'entrer.
    #[arg(long)]
    job_name: Option<String>,

    /// Nombre de threads que le notebook pourrait être amené à utiliser au maximum. Par défaut, 1.
    #[arg(long)]
    threads: Option<u32>,

    /// Ressources génériques SLURM que le notebook pourrait être amené à utiliser (ex: `--gres gpu:a100:2`). Aucune ressource générique par défaut.
    #[arg(long)]
    gres: Option<String>,

    /// Durée d'exécution maximale du notebook. Par défaut, 24 heures. Au-delà de 24 heures, un mail sera envoyé à l'administrateur système avec votre nom d'utilisateur sur le cluster.
    #[arg(long)]
    time: Option<String>,

    /// Quantité de mémoire nécessaire pour faire tourner le notebook. Par défaut, 1G.
    #[arg(long)]
    mem: Option<String>,

    /// Nom du noeud spécifique à utiliser pour lancer la commande. Si non spécifié, le choix du noeud reviendra à SLURM en fonction des ressources disponibles et celles demandées.
    #[arg(long)]
    node: Option<String>,

    /// Nom de l'image singularity à utiliser (sans l'extension, ni le chemin du dossier parent. Résolu comme `/SINGULARITIES/{image}.sif`)
    #[arg(long)]
    image: Option<String>,

    /// Dossier d'exécution du notebook. Par défaut, `$PWD`.
    #[arg(long)]
    directory: Option<PathBuf>,

    /// Chemin vers le fichier batch à exécuter. Valeur par défaut: `/OPT/notebooks/batch-scripts/notebook.sbatch`
    #[arg(long)]
    batch_script: Option<PathBuf>,
}

#[derive(Default, Debug)]
enum SqueueStatus {
    #[default]
    AnyOther,
    Running,
    Pending,
}

fn check_squeue_status(job_id: u64) -> SqueueStatus {
    // squeue -h -j "$jobid" -o "%T"

    Command::new("squeue")
        .arg("-h")
        .arg("-j")
        .arg(job_id.to_string())
        .arg("-o")
        .arg("%T")
        .output()
        .ok()
        .map(|res| match res.stdout.as_slice() {
            b"PENDING\n" => SqueueStatus::Pending,
            b"RUNNING\n" => SqueueStatus::Running,
            _ => SqueueStatus::AnyOther,
        })
        .unwrap_or_default()
}

fn main() -> anyhow::Result<()> {
    let args = SlurmNoteBookArgs::parse();
    let SlurmNoteBookArgs {
        job_name,
        threads,
        gres,
        time,
        mem,
        node,
        image,
        directory,
        batch_script,
    } = args;

    if let Some(d) = directory {
        std::env::set_current_dir(&d).with_context(|| {
            format!(
                "Impossible de modifier le dossier courant à {}",
                d.display()
            )
        })?;
    }

    let job_name = job_name.unwrap_or_else(|| {
        Text::new("Un nom de job est requis. Veuillez en entrer un.")
            .with_validator(|s: &str| {
                Ok(if !s.is_empty() {
                    Validation::Valid
                } else {
                    Validation::Invalid("Le nom du job ne peut pas être vide".into())
                })
            })
            .prompt()
            .expect("Impossible d'avoir un nom de job valide.")
    });

    // Par défaut, pour un notebook, un seul thread suffit.
    let threads = threads.unwrap_or(1);
    // Par défaut, n'allouer le notebook que pour 24 heures.
    let time = time.unwrap_or("24:00:00".to_string());
    // Par défaut, allouer 1G de mémoire.
    let mem = mem.unwrap_or("1G".to_string());

    let mut cmd = Command::new("sbatch");

    cmd.arg("--parsable") // Permet de récupérer le nom du job SLURM
        .arg("--job-name") // Nom du job
        .arg(&job_name)
        .arg("--cpus-per-task") // Nombre de threads
        .arg(threads.to_string())
        .arg("--time") // Durée d'exécution
        .arg(&time)
        .arg("--mem") // Quantité de mémoire demandée
        .arg(&mem)
        .arg("-A") // Account
        .arg("recherche")
        .arg("--nodes") // Nombre de noeuds
        .arg("1")
        .arg("--ntasks") // Nombre de tâches
        .arg("1");

    // Ressources génériques (cas particulier)
    if let Some(ref gres) = gres {
        cmd.arg("--gres").arg(gres);
    }

    // Demande d'un noeud spécifique
    if let Some(ref node) = node {
        if node.contains(",") {
            bail!(
                "Impossible de demander plusieurs noeuds pour un notebook. Il s'agit d'une restriction logique, une instance de jupyter notebook ne pouvant pas s'exécuter sur plusieurs noeuds à la fois..."
            );
        }
        cmd.arg("-w").arg(node);
    }

    // Demande d'une image singularity spécifique
    if let Some(ref image) = image {
        cmd.env("SIF_NAME", image);
    }

    if let Ok(home_dir) = std::env::var("HOME") {
        let usermail_filename = Path::new(&home_dir).join(".usermail");
        if !Path::exists(&usermail_filename)
            && Confirm::new("Voulez-vous ajouter votre adresse mail dans $HOME/.usermail afin d'être notifié pour les événements vous concernant ?").prompt().is_ok_and(|x|x)
            {
                let mut f = std::fs::File::create(&usermail_filename)?;
                std::write!(&mut f,"{}",Text::new("Veuillez entrer votre adresse mail").prompt().with_context(||"Vous n'avez pas entré d'adresse mail, rien n'a été fait.")?).with_context(||"Impossible de sauvegarder l'adresse mail utilisateur")?;
            }
    }

    // Ajouter le chemin vers le batch script à lancer
    let batch_script = batch_script.unwrap_or(PathBuf::from_str(
        "/OPT/notebooks/batch-scripts/notebook.sbatch",
    )?);
    cmd.arg(batch_script);

    let cmd_res = cmd
        .output()
        .with_context(|| "Impossible d'invoquer sbatch")?;

    if !cmd_res.status.success() {
        anyhow::bail!(
            "Erreur lors de la soumission du script sbatch: {}",
            String::from_utf8_lossy(&cmd_res.stderr)
        );
    } else {
        let job_id: u64 = String::from_utf8_lossy(&cmd_res.stdout)
            .trim()
            .parse()
            .with_context(|| {
                format!(
                    "Impossible de convertir en entier non signé 64 bits l'ID de job SLURM `{}`",
                    String::from_utf8_lossy(&cmd_res.stdout)
                )
            })?;
        println!(
            "Votre job a été soumis avec l'ID `{}`, veuillez patienter. Le temps d'attente peut varier selon la charge du cluster et la quantité de ressources demandée.\n",
            job_id
        );
        println!(
            "Vous avez demandé:\n- Nom du job: `{}`\n- Nombre de CPUs: `{}`\n- Durée: `{}`\n- Quantité de mémoire: `{}`\n",
            job_name, threads, time, mem
        );
        if let Some(ref node) = node {
            println!("- Noeud: `{}`\n", node);
        }
        if let Some(ref gres) = gres {
            println!("- Ressources génériques: `{}`\n", gres);
        }
        if let Some(ref image) = image {
            println!(
                "- Image singularity: `{0}` (fichier attendu dans /SINGULARITIES/{0}.sif)\n",
                image
            );
        }
        let mut loop_counter = 0;
        loop {
            let st = check_squeue_status(job_id);
            match st {
                SqueueStatus::Pending => {
                    if loop_counter > 0 {
                        println!("Toujours en attente de ressources...");
                    } else {
                        println!(
                            "Votre job est toujours en attente des ressources nécessaires. Attendons 5 secondes...\n(Vous pouvez interrompre ce programme avec Ctrl+C ou kill, le job a été soumis et ne sera pas annulé. Rappel du job id SLURM: {0})\nUne fois le job alloué et démarré, vous devriez recevoir un mail, même après avoir terminé ce programme. Sinon, cherchez les logs de sortie dans /OPT/notebooks/logs/notebook-{0}.out et /OPT/notebooks/logs/notebook-{0}.err",
                            job_id
                        );
                    }
                    sleep(Duration::from_secs(5));
                }
                SqueueStatus::Running => {
                    println!(
                    "Votre notebook est disponible à l'adresse suivante:\n{}",
                    std::fs::File::open(format!("/OPT/notebooks/running/notebook-{job_id}"))
                        .map(std::io::BufReader::new).map(|f|f.lines().map_while(Result::ok).collect::<Vec<_>>().join("\n")).with_context(||{
                            format!("Le fichier /OPT/notebooks/running/notebook-{job_id}.execinfo n'existe pas!")})?
                );
                    break;
                }
                SqueueStatus::AnyOther => {
                    println!(
                        "Votre job n'est ni en attente, ni en cours d'exécution. Veuillez contacter votre administrateur système pour comprendre ce qui a pu se passer. ID du job: {}",
                        job_id
                    );
                    break;
                }
            }
            loop_counter += 1;
        }
        Ok(())
    }
}
