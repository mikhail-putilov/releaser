import java.nio.file.Paths

def releaseVersion = '1.0.0'
def releaseBranchName = "release/$releaseVersion"
def checkpointTagName = "$releaseVersion-checkpoint"
def developBranchName = 'develop'


def project = new XmlSlurper().parse(new File("pom.xml"));
String currentDir = new File(".").getAbsolutePath()

/**
 * Run commands in all modules
 */
def run(commands) {
    // module dir -> executed commands
    executionLog = [:]
    project.modules.children().each {
        try {
            executionLog["$it"] = []
            def dir = Paths.get(currentDir, "$it")
            commands.each {
                try {
                    cmd.executeCommand()
                } finally {
                    // always put commands even if command failed
                    executionLog["$it"].add(cmd)
                }
            }
        } catch (RuntimeException e) {
            e.executionLog = executionLog
            throw e;
        }
    }
}

class Command {
    String cmd
    String failExplanation

    def executeCommand() {
        println command
        def process = command.execute()
        process.waitFor()

        if (process.exitValue()) {
            print "${process.err.text}\n"
            throw new RuntimeException("$command.failExplanation")
        }
        print process.in.text
    }
}

class GitCommand extends Command {
    def dir

    GitCommand(dir, cmd, failExplanation) {
        super(cmd: "git -C $dir $cmd", failExplanation: failExplanation)
        this.dir = dir
    }
}

def validateCommands = [
        new GitCommand(cmd: 'status --porcelain',
                failExplanation: 'working dir is not clean'),
        new GitCommand(cmd: "checkout $developBranchName",
                failExplanation: "cannot checkout $developBranchName branch"),
        new GitCommand(cmd: "pull origin $developBranchName",
                failExplanation: "cannot pull new changes for $developBranchName branch")
]
def checkpointCommand = new GitCommand(cmd: "tag $checkpointTagName",
        failExplanation: "cannot create checkpoint (git tag $checkpointTagName). Probably repository is in inconsistent state with the others")

///////////////////////////////////////////////////
try {
    run(validateCommands)
} catch (RuntimeException e) {
    println 'Cannot validate project. No changes have been made.'
    println e.message
    println 'Execution log:'
    println e.executionLog
}
try {
    run([checkpointCommand.executeCommand()])
} catch (RuntimeException e) {
    println 'Cannot create checkpoint.'
    println e.message
    println 'Execution log:'
    println e.executionLog
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