#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <termios.h>
#include <readline/readline.h>
#include <readline/history.h>

static inline FILE *apfel_get_rl_outstream(void) {
    return rl_outstream;
}

static inline void apfel_set_rl_outstream(FILE *stream) {
    rl_outstream = stream;
}

static inline FILE *apfel_get_rl_instream(void) {
    return rl_instream;
}

static inline void apfel_set_rl_instream(FILE *stream) {
    rl_instream = stream;
}

static volatile sig_atomic_t apfel_sigint_reset_stdout = 0;

// Terminal settings captured (in cooked mode) before libedit puts stdin into
// raw/no-echo mode for line editing. The SIGINT handler restores these so a
// Ctrl-C out of readline() does not leave the terminal in raw mode for the
// parent shell / wrapper (#251). tcsetattr is async-signal-safe.
// `used` forces the compiler to emit storage in every TU that references it.
// Without it, this address-taken file-scope static (tcgetattr/tcsetattr take
// its address) is left as an unemitted definition in TUs where the inline
// helpers land, producing an undefined-symbol link error.
static struct termios apfel_saved_termios __attribute__((used)) = {0};
static volatile sig_atomic_t apfel_have_saved_termios __attribute__((used)) = 0;

// Capture the current terminal settings as the "restore to" state. Called
// before readline() modifies the tty, while stdin is still in cooked mode.
static inline void apfel_capture_termios(void) {
    if (tcgetattr(STDIN_FILENO, &apfel_saved_termios) == 0) {
        apfel_have_saved_termios = 1;
    }
}

static inline void apfel_block_sigint(void) {
    sigset_t blocked;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGINT);
    pthread_sigmask(SIG_BLOCK, &blocked, NULL);
}

static void apfel_sigint_exit_handler(int sig) {
    (void)sig;

    static const char reset[] = "\033[0m";
    static const char newline[] = "\n";

    // Restore the terminal to its pre-readline (cooked) mode. libedit's
    // rl_deprep_terminal / atexit cleanup never runs on _exit(), so without
    // this the tty stays in raw/no-echo mode for the parent shell or wrapper.
    // tcsetattr is async-signal-safe (#251).
    if (apfel_have_saved_termios) {
        (void)tcsetattr(STDIN_FILENO, TCSAFLUSH, &apfel_saved_termios);
    }

    if (apfel_sigint_reset_stdout) {
        (void)write(STDOUT_FILENO, reset, sizeof(reset) - 1);
    }
    (void)write(STDERR_FILENO, newline, sizeof(newline) - 1);
    _exit(130);
}

/// Install a signal-safe SIGINT handler that exits immediately with code 130.
static inline void apfel_install_sigint_exit_handler(int resetStdout) {
    struct sigaction sa;
    sigset_t unblock;
    sigemptyset(&sa.sa_mask);
    sa.sa_handler = apfel_sigint_exit_handler;
    sa.sa_flags = 0;

    apfel_sigint_reset_stdout = resetStdout ? 1 : 0;
    sigaction(SIGINT, &sa, NULL);

    sigemptyset(&unblock);
    sigaddset(&unblock, SIGINT);
    pthread_sigmask(SIG_UNBLOCK, &unblock, NULL);
}

/// Read a line with SIGINT unblocked and a C-level exit handler installed.
/// Some runtime/model setup can leave SIGINT masked before chat input begins.
static inline char *apfel_readline_interruptible(const char *prompt) {
    struct sigaction sa;
    struct sigaction previous;
    sigset_t unblock;
    sigset_t previous_mask;
    char *line;

    apfel_sigint_reset_stdout = isatty(STDOUT_FILENO) != 0;

    // Snapshot the cooked terminal state before readline() switches to raw
    // mode, so the SIGINT handler can restore it on Ctrl-C (#251).
    apfel_capture_termios();

    sigemptyset(&sa.sa_mask);
    sa.sa_handler = apfel_sigint_exit_handler;
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, &previous);

    sigemptyset(&unblock);
    sigaddset(&unblock, SIGINT);
    pthread_sigmask(SIG_UNBLOCK, &unblock, &previous_mask);

    line = readline(prompt);
    pthread_sigmask(SIG_SETMASK, &previous_mask, NULL);
    sigaction(SIGINT, &previous, NULL);
    return line;
}
