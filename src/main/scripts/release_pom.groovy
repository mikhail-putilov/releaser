import java.nio.file.Paths

def releaseVersion = '1.0.0'
def releaseBranchName = "release/$releaseVersion"
def checkpointTagName = "$releaseVersion-checkpoint"
def developBranchName = 'develop'

enum ExitStatus {
    SUCCESS, FAILFAST, READY

    static def getStatusByExitCode(int exitStatus) {
        exitStatus == 0 ? SUCCESS : FAILFAST
    }
}

class Command {
    String cmd
    String failExplanation

    def executeCommand() {
        println command
        def process = command.execute()
        process.waitFor()
        def exitStatus = ExitStatus.getStatusByExitCode(process.exitValue())
        if (exitStatus == ExitStatus.FAILFAST) {
            print "${process.err.text}\n"
            throw new RuntimeException("$command.failExplanation")
        }
        print process.in.text
        exitStatus
    }
}

class GitCommand extends Command {
    String dir
    GitCommand(dir, cmd, failExplanation) {
        super(cmdPrefix: "git -C $dir", cmd: cmd, failExplanation: failExplanation)
    }
}

def exitStatus = ExitStatus.READY
def project = new XmlSlurper().parse(new File("pom.xml"));
def currentDir = new File(".").getAbsolutePath()

def validateCommands = [
        new GitCommand(cmd: 'status --porcelain',
                failExplanation: 'working dir is not clean'),
        new GitCommand(cmd: "checkout $developBranchName",
                failExplanation: "cannot checkout $developBranchName branch"),
        new GitCommand(cmd: "pull origin $developBranchName",
                failExplanation: "cannot pull new changes for $developBranchName branch"),
        new GitCommand(cmd: "tag $checkpointTagName",
                failExplanation: "cannot create checkpoint (git tag $checkpointTagName). Probably repository is in inconsistent state with the others"),
]

def checkpointCommand = new Command(cmd: "checkout -b $releaseBranchName",
        failExplanation: "cannot create release branch: $releaseBranchName")
def setReleaseVersionsByMvn = new Command(cmd: """mvn versions:set -DgenerateBackupPoms=false
    -DprocessAllModules=true
    -DnewVersion="1.0.0"
    -DoldVersion=*
    -DgroupId=*
    -DartifactId=*""", failExplanation: 'Maven cannot update version of all modules')




project.modules.children().each {
    def dir = Paths.get(currentDir, "$it")
    def git = "git -C $dir"
    validateCommands.each {
        executeCommand("$git $it")
    }
}

checkpointCommand.executeCommand()
setReleaseVersionsByMvn.executeCommand()


new Command(cmd: "checkout -b $releaseBranchName", failExplanation: "cannot create release branch: $releaseBranchName")

return exitCode