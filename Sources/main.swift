//
//  main.swift
//  seahaven
//
//  Created by Michael Bass on 2/9/24.
//

import Foundation
import ANSITerminal

extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

let ABANDON_THRESHOLD = 500000

enum Rank: Int {
    case ace = 1
    case two, three, four, five, six, seven, eight, nine, ten
    case jack, queen, king
    
    func name() -> String {
        switch self {
        case .ace:
            return "A"
        case .jack:
            return "J"
        case .queen:
            return "Q"
        case .king:
            return "K"
        default:
            return String(self.rawValue)
        }
    }
}

enum Suit: Int {
    case spades, hearts, diamonds, clubs
    
    func name() -> String {
        switch self {
            case .spades: return "S"
            case .hearts: return "H"
            case .diamonds: return "D"
            case .clubs: return "C"
        }
    }
}

struct Card {
    let rank: Rank
    let suit: Suit
    
    func name() -> String { return "\(rank.name())\(suit.name()) "}
    func coloredName() -> String { 
		let text = name()
		switch suit {
			case .spades:  return  text.asBlue 
			case .hearts: return text.asRed
			case .diamonds: return text.asLightRed
			case .clubs: return text.asLightBlue
		}
	}
}

struct Tally {
	var totalGames = 0
	var winnable = 0
	var losers = 0
	var abandoned = 0
}



struct Position {
    var index: Int
    var type: Int
}

struct Move {
	let source: Position
	let target: Position
	let extent: Int 
}
    
// Used for hashing and sorting the deck
func cardValue(card: Card?) -> Int {
    if let c = card {
        return c.suit.rawValue * 100 + c.rank.rawValue
    }
    return 0
}

func cardName(card: Card?,fallback: String) -> String {
	if let c = card {
		return c.name()
	}
	return fallback
}

func cardColoredName(card: Card?,fallback: String) -> String {
	if let c = card {
		return c.coloredName()
	}
	return fallback
}

class Stack {
    var pile:[Card] = []
}

enum StackType: Int {
    case GOAL, CELL, TABLEAU
}

class Board {
    var goals:[Stack] = []
    var cells:[Stack] = []
    var stacks:[Stack] = []
    
    // Initialize the board
    init() {
        
        var deck: [Card] = []
        for suit in 0...3 {
            for value in 1...13 {
                let card = Card(rank:Rank(rawValue: value)!,suit:Suit(rawValue: suit)!)
                deck.append(card)
            }
        }
        deck.shuffle()
        
        // init each of the 10 stacks with 5 cards each
        for _ in 1...10 {
            let stack = Stack()
            for _ in 1...5 {
                let card = deck.popLast()!
                stack.pile.append(card)
            }
            stacks.append(stack)
        }
                        
        for _ in 1...4 { goals.append(Stack())}
        for _ in 1...4 { cells.append(Stack())}
                
    }
}


class Game {
	var board: Board
	var stackSize = 0
	var totalMoves = 0
	var repeatesAvoided = 0
	var tally:Tally
	var gameMoves: [Move] = []
	var abandoned = false

    init(fromTally tally: Tally) {
        board = Board()
		self.tally = tally
    }

	func print(title: String) {
	
		moveTo(1,1)
		write(title)
	
		let offsetY = 2
	
		// // print goals
		for (i,goalStack) in board.goals.enumerated() {
			moveTo(offsetY+1,1+(i  * 4))					
			write(cardColoredName(card: goalStack.pile.last, fallback: " - "))			
		}
		
		
		for (i,cellStack) in board.cells.enumerated() {
			moveTo(offsetY+1,30+(i  * 4));
			write(cardColoredName(card: cellStack.pile.last, fallback: " x "))						
		}
		// // find the max length of the stacks
		let maxLength = self.board.stacks.map({ $0.pile.count}).max()! + 10
	
		for row in 0..<maxLength {		
			for (col,tableStack) in board.stacks.enumerated() {
				moveTo(offsetY+3+row,1+(col*4))	
				let card = tableStack.pile[safe: row]								
				write(cardColoredName(card: card, fallback: " x "))						
			}
		}
	
		// term.act(Action::SetForegroundColor(Color::Reset));
	
		// term.act(Action::MoveCursorTo(50,offsetY+2));
		// print!("Games Played {0}",self.tally.totalGames);
		// term.act(Action::MoveCursorTo(50,offsetY+4));
		// print!("Winnable {0}  Losers: {1}  Abandoned {2}",self.tally.winnable,self.tally.losers,self.tally.abandoned);
		// term.act(Action::MoveCursorTo(50,offsetY+6));
		// print!("Stack Size {0}",self.stackSize);
		// term.act(Action::MoveCursorTo(50,offsetY+8));
		// print!("Total Moves {0}",self.totalMoves);
		// term.act(Action::MoveCursorTo(50,offsetY+10));
		// print!("Unique Boards {0}  Collisions: {1}",self.boardSet.len(),self.repeatsAvoided);
		
	
	}		
    
}

func main() {
    clearScreen()
    var tally = Tally()
    var game = Game(fromTally: tally)
	game.print(title: "Testing")
}


main()
