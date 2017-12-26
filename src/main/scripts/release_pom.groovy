import java.nio.file.Paths

def releaseVersion = '1.0.0'
def releaseBranchName = "release/$releaseVersion"
def checkpointTagName = "$releaseVersion-checkpoint"
def developBranchName = 'develop'


def project = new XmlSlurper().parse(new File("pom.xml"));
currentDir = new File(".").getAbsolutePath()
profile = project.profiles.children().find { profile ->
    profile.id == 'sub-modules'
}
class Phase {
    String phaseTitle
    String phaseFailAdditional
    List<Command> cmds
    Phase(phaseTitle, phaseFailAdditional, cmds) {
        this.phaseTitle = phaseTitle
        this.phaseFailAdditional = phaseFailAdditional
        this.cmds = cmds
    }
    def runPhase() {
        try {
            println "***** $phaseTitle *****"
            run(cmds)
        } catch (RuntimeException e) {
            System.err.println "Exception during $phaseTitle. $phaseFailAdditional\nException message:"
            System.err.println e.message
            e.printStackTrace()
            System.err.println "Execution log of the phase ${phaseTitle.toLowerCase}:"
            System.err.println e.executionLog
        }
    }
}
/**
 * Run commands in all modules
 */
def run(commands) {
    // module dir -> executed commands
    executionLog = [:]
    profile.modules.children().each {
        try {
            String currentModule = "$it".toString()
            executionLog[currentModule] = []
            def dir = Paths.get(currentDir, "$it")
            commands.each {
                try {
                    it.prepare(dir)
                    it.executeCommand()
                } finally {
                    // always put commands even if command failed
                    executionLog[currentModule].add(it)
                }
            }
        } catch (RuntimeException e) {
            e.metaClass.executionLog = executionLog
            throw e;
        }
    }
}

class Command {
    String cmd
    String failExplanation

    Command(cmd, failExplanation) {
        this.cmd = cmd
        this.failExplanation = failExplanation
    }

    def executeCommand() {
        println cmd
        def process = cmd.execute()
        process.waitFor()

        if (process.exitValue()) {
            print "${process.err.text}\n"
            throw new RuntimeException(failExplanation)
        }
        print process.in.text
    }

    void prepare(dir) {
        // noop
    }

    String toString() {
        return cmd
    }
}

class GitCommand extends Command {
    def dir
    def subcmd

    GitCommand(String subcmd, String failExplanation) {
        super('', failExplanation)
        this.subcmd = subcmd
    }

    void prepare(dir) {
        this.dir = dir
        this.cmd = "git -C $dir $subcmd"
    }

    String toString() {
        return "git $subcmd"
    }
}

def validateCommands = [
        new GitCommand('status --porcelain',
                'working dir is not clean'),
        new GitCommand("checkout $developBranchName",
                "cannot checkout $developBranchName branch"),
        new GitCommand("pull origin $developBranchName",
                "cannot pull new changes for $developBranchName branch")
]

validatePhase = new Phase("Validation", "No chanes have been made", validateCommands)
def checkpointCommand = new GitCommand("tag $checkpointTagName",
        "cannot create checkpoint (git tag $checkpointTagName). Probably repository is in inconsistent state with the others")

///////////////////////////////////////////////////
try {
    run(validateCommands)
} catch (RuntimeException e) {
    System.err.println 'Cannot validate project. No changes have been made. Exception message:'
    System.err.println e.message
    e.printStackTrace()
    System.err.println 'Execution log:'
    System.err.println e.executionLog
}
try {
    run([checkpointCommand])
} catch (RuntimeException e) {
    System.err.println 'Cannot create checkpoint.'
    System.err.println e.message
    e.printStackTrace()
    System.err.println 'Execution of the log:'
    System.err.println e.executionLog
}
//
//def createReleaseBranchCommand = new Command(cmd: "checkout -b $releaseBranchName",
//        failExplanation: "cannot create release branch: $releaseBranchName")
//def setReleaseVersionsByMvnCommand = new Command(cmd: """mvn versions:set -DgenerateBackupPoms=false
//    -DprocessAllModules=true
//    -DnewVersion="${releaseVersion}"
//    -DoldVersion=*
//    -DgroupId=*
//    -DartifactId=*""", failExplanation: 'Maven cannot update version of all modules')
//
//checkpointCommand.executeCommand()
//currentState = ExitStatus.SUCCESS // now we have something to lose, because we created checkpoint
//
//setReleaseVersionsByMvnCommand.executeCommand()
//
//
//new Command(cmd: "checkout -b $releaseBranchName", failExplanation: "cannot create release branch: $releaseBranchName")
//
//checkpointCommand
//        .success(createReleaseBranchCommand)
//        .error()
//return exitCode