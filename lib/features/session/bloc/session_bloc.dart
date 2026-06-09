import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_chat/features/session/models/session_model.dart';
import 'package:offline_chat/features/session/repositories/session_repository.dart';

// Events
sealed class SessionEvent extends Equatable {
  const SessionEvent();

  @override
  List<Object?> get props => [];
}

class SessionsLoaded extends SessionEvent {
  const SessionsLoaded();
}

class SessionCreated extends SessionEvent {
  final String? title;
  const SessionCreated({this.title});
}

class SessionSelected extends SessionEvent {
  final String id;
  const SessionSelected(this.id);

  @override
  List<Object?> get props => [id];
}

class SessionDeleted extends SessionEvent {
  final String id;
  const SessionDeleted(this.id);

  @override
  List<Object?> get props => [id];
}

class SessionTitleUpdated extends SessionEvent {
  final String id;
  final String title;
  const SessionTitleUpdated(this.id, this.title);

  @override
  List<Object?> get props => [id, title];
}

// States
sealed class SessionState extends Equatable {
  const SessionState();

  @override
  List<Object?> get props => [];
}

class SessionInitial extends SessionState {
  const SessionInitial();
}

class SessionLoading extends SessionState {
  const SessionLoading();
}

class SessionLoaded extends SessionState {
  final List<SessionModel> sessions;
  final String? activeSessionId;

  const SessionLoaded({required this.sessions, this.activeSessionId});

  @override
  List<Object?> get props => [sessions, activeSessionId];
}

class SessionError extends SessionState {
  final String message;
  const SessionError(this.message);

  @override
  List<Object?> get props => [message];
}

// Bloc
class SessionBloc extends Bloc<SessionEvent, SessionState> {
  final SessionRepository _sessionRepository;

  // FIX #4: Cache sessions list để dùng được trong mọi state
  List<SessionModel> _cachedSessions = [];

  SessionBloc(this._sessionRepository) : super(const SessionInitial()) {
    on<SessionsLoaded>(_onSessionsLoaded);
    on<SessionCreated>(_onSessionCreated);
    on<SessionSelected>(_onSessionSelected);
    on<SessionDeleted>(_onSessionDeleted);
    on<SessionTitleUpdated>(_onSessionTitleUpdated);
  }

  Future<void> _onSessionsLoaded(
    SessionsLoaded event,
    Emitter<SessionState> emit,
  ) async {
    emit(const SessionLoading());
    try {
      final sessions = await _sessionRepository.getAllSessions();
      _cachedSessions = sessions;
      emit(SessionLoaded(sessions: sessions));
    } catch (e) {
      emit(SessionError(e.toString()));
    }
  }

  Future<void> _onSessionCreated(
    SessionCreated event,
    Emitter<SessionState> emit,
  ) async {
    try {
      final session =
          await _sessionRepository.createSession(title: event.title);
      final sessions = await _sessionRepository.getAllSessions();
      _cachedSessions = sessions;
      emit(SessionLoaded(sessions: sessions, activeSessionId: session.id));
    } catch (e) {
      emit(SessionError(e.toString()));
    }
  }

  // FIX #4: Dùng _cachedSessions nếu state không phải SessionLoaded
  // (ví dụ đang SessionLoading hoặc vừa navigate lại)
  void _onSessionSelected(
    SessionSelected event,
    Emitter<SessionState> emit,
  ) {
    final sessions = state is SessionLoaded
        ? (state as SessionLoaded).sessions
        : _cachedSessions;

    emit(SessionLoaded(
      sessions: sessions,
      activeSessionId: event.id,
    ));
  }

  Future<void> _onSessionDeleted(
    SessionDeleted event,
    Emitter<SessionState> emit,
  ) async {
    emit(const SessionLoading());
    try {
      await _sessionRepository.deleteSession(event.id);
      final sessions = await _sessionRepository.getAllSessions();
      _cachedSessions = sessions;
      emit(SessionLoaded(
        sessions: sessions,
        activeSessionId: null,
      ));
    } catch (e) {
      emit(SessionError(e.toString()));
    }
  }

  Future<void> _onSessionTitleUpdated(
    SessionTitleUpdated event,
    Emitter<SessionState> emit,
  ) async {
    try {
      await _sessionRepository.updateSessionTitle(event.id, event.title);
      final sessions = await _sessionRepository.getAllSessions();
      _cachedSessions = sessions;
      emit(SessionLoaded(
        sessions: sessions,
        activeSessionId: event.id,
      ));
    } catch (e) {
      emit(SessionError(e.toString()));
    }
  }
}
