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
}

def exitStatus = ExitStatus.READY
def project = new XmlSlurper().parse(new File("pom.xml"));
def currentDir = new File(".").getAbsolutePath()

def validateCommands = [
        new Command(cmd: 'status --porcelain',
                failExplanation: 'working dir is not clean'),
        new Command(cmd: "checkout $developBranchName",
                failExplanation: "cannot checkout $developBranchName branch"),
        new Command(cmd: "pull origin $developBranchName",
                failExplanation: "cannot pull new changes for $developBranchName branch"),
        new Command(cmd: "tag $checkpointTagName",
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


def executeCommand(command) {
    println command
    def process = command.execute()
    process.waitFor()
    def exitStatus = ExitStatus.getStatusByExitCode(process.exitValue())
    print exitStatus == ExitStatus.FAILFAST ? "${process.err.text}\n" : process.in.text
    exitStatus
}

project.modules.children().each {
    def dir = Paths.get(currentDir, "$it")
    def git = "git -C $dir"
    validateCommands.each {
        if (exitStatus == ExitStatus.FAILFAST) throw new RuntimeException("Fail fast! $it.failExplanation. Couldn't process command '$it.cmd'")
        exitStatus = executeCommand("$git $it")
    }
}

executeCommand(checkpointCommand)
executeCommand(setReleaseVersionsByMvn)


new Command(cmd: "checkout -b $releaseBranchName", failExplanation: "cannot create release branch: $releaseBranchName")

return exitCode