import org.slf4j.Logger
import org.slf4j.LoggerFactory

import java.nio.file.Paths

def releaseVersion = '1.0.0'
def releaseBranchName = "release/$releaseVersion"
def checkpointTagName = "$releaseVersion-checkpoint"
def developBranchName = 'develop'
def releaseCommitMessage = "\"Release_v$releaseVersion\""

def project = new XmlSlurper().parse(new File('pom.xml'));
def currentDir = new File('.').getAbsolutePath()
def modules = project
        .profiles
        .children()
        .find { it.id == 'sub-modules' }
        .modules
        .children()
        .collect { Paths.get(currentDir, it.text()).normalize() }
currentDir = Paths.get(currentDir).normalize()
def allModules = modules.clone()
allModules.add(currentDir)

class Phase {
    Logger log
    def dirs
    String title
    def cmds
    boolean ignoreExitCode

    Phase(dirs, title, cmds, ignoreExitCode = false) {
        this.ignoreExitCode = ignoreExitCode
        this.dirs = dirs
        this.title = title
        this.cmds = cmds
        this.log = LoggerFactory.getLogger(this.title)
    }

    def run() {
        try {
            dirs.each { dir ->
                log.info "--- $title @ $dir ---"
                cmds.each { cmd ->
                    log.info "$cmd"
                    if (cmd.startsWith('git')) {
                        cmd = cmd.replace('git', "git -C $dir")
                        log.trace "Actual command is $cmd"
                    }
                    def process = cmd.execute()
                    process.waitFor()

                    def isBadExitValue = !ignoreExitCode && process.exitValue()
                    if (cmd.contains('show-ref --verify')) {
                        isBadExitValue = !isBadExitValue
                    }
                    if (isBadExitValue) {
                        throw new RuntimeException("failed: $cmd\nerror text: ${process.err.text ?: 'no error text'}")
                    }
//                log.info process.in.text
                }
            }
            log.info "------------------------------------------------------------------------"
            log.info "${title.toUpperCase()} SUCCESS"
            log.info "------------------------------------------------------------------------"
        } catch (Throwable t) {
            log.info "------------------------------------------------------------------------"
            log.info "${title.toUpperCase()} FAILED"
            log.info "------------------------------------------------------------------------"
            throw t
        }
    }
}

def validateCommands = [
        'git status --porcelain',
        'git diff --exit-code',
        "git show-ref --verify \"refs/heads/${releaseBranchName}\"",
        "git checkout $developBranchName",
        "git pull origin $developBranchName"
]

def validationPhase = new Phase(modules, 'Validation Phase', validateCommands)
//validationPhase.run()

def checkpointCommand = ["git tag $checkpointTagName"]
def deleteCheckpointCommand = ["git tag -d $checkpointTagName"]
def checkpointPhase = new Phase(modules, 'Checkpoint Phase', checkpointCommand)
//checkpointPhase.run()

def createReleaseCommands = [
        "git checkout $checkpointTagName",
        "git checkout -b $releaseBranchName",
        """mvn versions:set -DgenerateBackupPoms=false
    -DprocessAllModules=true
    -DnewVersion="${releaseVersion}"
    -DoldVersion=*
    -DgroupId=*
    -DartifactId=*""",
        "git add -u .",
        "git commit --message=$releaseCommitMessage"
]
try {
    def createReleasePhase = new Phase(modules, 'Release Branching Phase', createReleaseCommands)
    createReleasePhase.run()
} catch (Throwable e) {
    def rollbackPhase = new Phase(modules, 'Rollback Phase', ["git checkout develop",
                                                              "git reset --hard $checkpointTagName",
                                                              "git branch -D $releaseBranchName"], true)
    rollbackPhase.run()
    throw e
} finally {
    def deleteCheckpointPhase = new Phase(modules, 'Delete Checkpoint Phase', deleteCheckpointCommand)
    deleteCheckpointPhase.run()

}
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